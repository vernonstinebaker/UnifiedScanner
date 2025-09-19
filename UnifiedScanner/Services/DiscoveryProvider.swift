import Foundation
import Combine

final class ScanProgress: ObservableObject {
    @Published var totalHosts: Int = 0
    @Published var completedHosts: Int = 0
    @Published var started: Bool = false
    @Published var finished: Bool = false
    @Published var successHosts: Int = 0

    private func log(_ msg: String) {
        print("[Progress] \(msg)")
    }

    func reset() {
        log("reset (prev total=\(totalHosts) completed=\(completedHosts) success=\(successHosts))")
        totalHosts = 0
        completedHosts = 0
        successHosts = 0
        started = false
        finished = false
    }

    fileprivate func begin(total: Int) {
        log("begin total=\(total)")
        started = true
        finished = false
        completedHosts = 0
        successHosts = 0
        totalHosts = total
    }
}

public protocol DiscoveryProvider: AnyObject, Sendable {
    var name: String { get }
    func start() -> AsyncStream<Device>
    func stop()
}

// Stub provider examples (future real implementations will replace)
public final class MockMDNSProvider: DiscoveryProvider {
    public let name = "mock-mdns"
    private var cancelled = false
    public init() {}
    public func start() -> AsyncStream<Device> {
        cancelled = false
        return AsyncStream { continuation in
            Task { [weak self] in
                guard let self else { return }
                let samples = [
                    Device(primaryIP: "192.168.1.50", ips: ["192.168.1.50"], hostname: "apple-tv.local", discoverySources: [.mdns], services: []),
                    Device(primaryIP: "192.168.1.51", ips: ["192.168.1.51"], hostname: "printer.local", discoverySources: [.mdns], services: [])
                ]
                for dev in samples {
                    if Task.isCancelled { break }
                    let isCancelled = self.cancelled
                    if isCancelled { break }
                    continuation.yield(dev)
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                continuation.finish()
            }
        }
    }
    public func stop() { cancelled = true }
}

// MARK: - PingOrchestrator
public actor PingOrchestrator {
    private let pinger: Pinger
    private let store: DeviceSnapshotStore
    private let maxConcurrent: Int
    private var active: Set<String> = []
    private var progress: ScanProgress?

    init(pinger: Pinger, store: DeviceSnapshotStore, maxConcurrent: Int = 32, progress: ScanProgress? = nil) {
        self.pinger = pinger
        self.store = store
        self.maxConcurrent = maxConcurrent
        self.progress = progress
    }

    func currentProgress() -> ScanProgress? { progress }

    public func enqueue(hosts: [String], config: PingConfig) async {
        let logging = (ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1")
        if let progress = self.progress {
            await MainActor.run {
                if !progress.started {
                    progress.started = true
                    if logging { print("[Ping] forcing progress.started=true (late start)") }
                }
                if progress.totalHosts == 0 {
                    if logging { print("[Ping][WARN] enqueue before progress total set (hosts=\(hosts.count))") }
                }
            }
        } else {
            if logging { print("[Ping][WARN] enqueue without progress reference") }
        }
        if logging { print("[Ping] enqueue batch size=\(hosts.count)") }
        for host in hosts {
            if logging { print("[Ping] queue host=\(host)") }
            await throttleIfNeeded()
            await launch(host: host, baseConfig: config)
        }
    }

    private func throttleIfNeeded() async {
        let logging = (ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1")
        if active.count >= maxConcurrent {
            if logging { print("[Ping] throttle waiting active=\(active.count) max=\(maxConcurrent)") }
        }
        while active.count >= maxConcurrent {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func launch(host: String, baseConfig: PingConfig) async {
        let logging = (ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1")
        if logging { print("[Ping] launch start host=\(host) active(before)=\(active.count)") }
        active.insert(host)
        let storeRef = store
        let progressRef = progress
        Task { [pinger] in
            if logging { print("[Ping] creating stream for host=\(host)") }
            let stream = await pinger.pingStream(config: PingConfig(host: host, count: baseConfig.count, interval: baseConfig.interval, timeoutPerPing: baseConfig.timeoutPerPing))
            var sawSuccess = false
            var measurementCount = 0
            for await m in stream {
                measurementCount += 1
                if logging { print("[Ping] measurement \(measurementCount) for host=\(host): \(m.status)") }
                if case .success = m.status { sawSuccess = true }
                await MainActor.run { storeRef.applyPing(m) }
            }
            if logging { print("[Ping] stream complete host=\(host) sawSuccess=\(sawSuccess) measurements=\(measurementCount)") }
            await self.didFinish(host: host, sawSuccess: sawSuccess)
            if let progressRef, sawSuccess { await MainActor.run { progressRef.successHosts += 1 } }
        }
    }

    private func didFinish(host: String, sawSuccess: Bool) async {
        let logging = (ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1")
        active.remove(host)
        if let progress = progress {
            await MainActor.run {
                let oldCompleted = progress.completedHosts
                progress.completedHosts += 1
                if logging { print("[Ping] didFinish host=\(host) completed=\(progress.completedHosts)/\(progress.totalHosts) success=\(sawSuccess) (was \(oldCompleted))") }
                if progress.totalHosts == 0 {
                    if logging { print("[Ping][WARN] progress.totalHosts still 0 at didFinish (race condition)") }
                } else if progress.completedHosts >= progress.totalHosts {
                    progress.finished = true
                    if logging { print("[Ping] progress finished (completed=\(progress.completedHosts) total=\(progress.totalHosts))") }
                }
            }
        } else {
            if logging { print("[Ping][WARN] didFinish with no progress reference host=\(host)") }
        }
    }
}

// MARK: - DiscoveryCoordinator
actor DiscoveryCoordinator {
    private let store: DeviceSnapshotStore
    private let pingOrchestrator: PingOrchestrator
    private let providers: [DiscoveryProvider]
    private let hostEnumerator: HostEnumerator
    private let arpReader: ARPTableReader
    private var tasks: [Task<Void, Never>] = []
    private var started = false

    init(store: DeviceSnapshotStore, pingOrchestrator: PingOrchestrator, providers: [DiscoveryProvider], hostEnumerator: HostEnumerator = LocalSubnetEnumerator(), arpReader: ARPTableReader = ARPTableReader()) {
        self.store = store
        self.pingOrchestrator = pingOrchestrator
        self.providers = providers
        self.hostEnumerator = hostEnumerator
        self.arpReader = arpReader
    }

    func start(pingHosts: [String], pingConfig: PingConfig, mdnsWarmupSeconds: Double = 2.0, autoEnumerateIfEmpty: Bool = true, maxAutoEnumeratedHosts: Int = 256) {
        guard !started else { return }
        started = true
        for provider in providers {
            let stream = provider.start()
            let t = Task {
                for await dev in stream {
                    await MainActor.run { self.store.upsert(dev, source: .mdns) }
                }
            }
            tasks.append(t)
        }
        Task { [pingHosts, pingConfig, autoEnumerateIfEmpty, maxAutoEnumeratedHosts] in
            try? await Task.sleep(nanoseconds: UInt64(mdnsWarmupSeconds * 1_000_000_000))
            var hosts = pingHosts
            if hosts.isEmpty, autoEnumerateIfEmpty {
                let enumerated: [String]
                if hostEnumerator is LocalSubnetEnumerator { // optimized fast static path
                    enumerated = LocalSubnetEnumerator.enumerate(maxHosts: maxAutoEnumeratedHosts)
                } else {
                    enumerated = hostEnumerator.enumerate(maxHosts: maxAutoEnumeratedHosts)
                }
                if !enumerated.isEmpty { hosts = enumerated }
                if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
                    print("[Discovery] auto-enumerated hosts count=\(hosts.count)")
                }
            }
            if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
                print("[Discovery] starting ping batch size=\(hosts.count)")
            }
            if let progress = await self.pingOrchestrator.currentProgress() {
                if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
                    print("[Discovery] calling progress.begin total=\(hosts.count)")
                }
                await MainActor.run { progress.begin(total: hosts.count) }
                if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
                    print("[Discovery] progress after begin total=\(progress.totalHosts) started=\(progress.started)")
                }
            }
            if hosts.isEmpty {
                if let progress = await self.pingOrchestrator.currentProgress() {
                    await MainActor.run { progress.finished = true }
                }
                return
            }

            // Start ping operations
            await self.pingOrchestrator.enqueue(hosts: hosts, config: pingConfig)

            // After ping operations complete, read ARP table to get MAC addresses
            if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
                print("[Discovery] ping operations enqueued, waiting for completion before ARP table read")
            }

            // Wait for ping operations to complete
            let progressRef = await self.pingOrchestrator.currentProgress()
            if let progress = progressRef {
                // Poll for completion
                while !progress.finished {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                }
            }

            // After ping operations complete, send broadcast UDP to populate ARP table
            if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
                print("[Discovery] ping operations complete, sending broadcast UDP")
            }

            // Extract subnet from first host (assuming /24 subnet)
            if let firstHost = hosts.first {
                let subnet = firstHost.split(separator: ".").prefix(3).joined(separator: ".") + ".0"
                await NetworkPinger.sendBroadcastUDP(for: subnet, timeout: 1.0)
            }

            // Read ARP table to get MAC addresses
            if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
                print("[Discovery] reading ARP table")
            }

            let ipToMac = await self.arpReader.getMACAddresses(for: Set(hosts), delaySeconds: 0.5)

            // Update devices with MAC addresses
            if !ipToMac.isEmpty {
                await MainActor.run {
                    for (ip, mac) in ipToMac {
                        // Find device by IP and update MAC address
                        if let existingDevice = self.store.devices.first(where: { $0.primaryIP == ip || $0.ips.contains(ip) }) {
                            if existingDevice.macAddress == nil || existingDevice.macAddress!.isEmpty {
                                var updatedDevice = existingDevice
                                updatedDevice.macAddress = mac
                                self.store.upsert(updatedDevice, source: .ping)
                                if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
                                    print("[Discovery] updated \(ip) with MAC \(mac)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func stop() {
        for t in tasks { t.cancel() }
        tasks.removeAll()
    }
}
