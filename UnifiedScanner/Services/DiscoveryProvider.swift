import Foundation
import Combine

actor ScanProgress: ObservableObject {
    @MainActor @Published var totalHosts: Int = 0
    @MainActor @Published var completedHosts: Int = 0
    @MainActor @Published var started: Bool = false
    @MainActor @Published var finished: Bool = false
    @MainActor @Published var successHosts: Int = 0

    private nonisolated func log(_ msg: String) {
        print("[Progress] \(msg)")
    }

    func reset() async {
        await MainActor.run {
            log("reset (prev total=\(totalHosts) completed=\(completedHosts) success=\(successHosts))")
            totalHosts = 0
            completedHosts = 0
            successHosts = 0
            started = false
            finished = false
        }
    }

    func begin(total: Int) async {
        await MainActor.run {
            log("begin total=\(total)")
            started = true
            finished = false
            completedHosts = 0
            successHosts = 0
            totalHosts = total
        }
    }

    func incrementCompleted() async {
        await MainActor.run {
            completedHosts += 1
            if completedHosts >= totalHosts && totalHosts > 0 {
                finished = true
                log("finished (completed=\(completedHosts) total=\(totalHosts))")
            }
        }
    }

    func incrementSuccess() async {
        await MainActor.run {
            successHosts += 1
        }
    }

    func getCurrentProgress() async -> (total: Int, completed: Int, success: Int, started: Bool, finished: Bool) {
        await MainActor.run {
            (totalHosts, completedHosts, successHosts, started, finished)
        }
    }
}

public protocol DiscoveryProvider: AnyObject, Sendable {
    var name: String { get }
    func start() -> AsyncStream<Device>
    func stop()
}

// Stub provider examples (future real implementations will replace)
public final class MockMDNSProvider: @unchecked Sendable, DiscoveryProvider {
    public let name = "mock-mdns"
    private let cancelledLock = NSLock()
    private var _cancelled = false
    public init() {}

    private var cancelled: Bool {
        get {
            cancelledLock.lock()
            defer { cancelledLock.unlock() }
            return _cancelled
        }
        set {
            cancelledLock.lock()
            defer { cancelledLock.unlock() }
            _cancelled = newValue
        }
    }

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
                    if self.cancelled { break }
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
    private let pingService: PingService
    private let store: DeviceSnapshotStore
    private let maxConcurrent: Int
    private var active: Set<String> = []
    private var progress: ScanProgress?

    init(pingService: PingService, store: DeviceSnapshotStore, maxConcurrent: Int = 32, progress: ScanProgress? = nil) {
        self.pingService = pingService
        self.store = store
        self.maxConcurrent = maxConcurrent
        self.progress = progress
    }

    func currentProgress() -> ScanProgress? { progress }

    public func enqueue(hosts: [String], config: PingConfig) async {
        let logging = (ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1")
        if let progress = self.progress {
            let current = await progress.getCurrentProgress()
            if !current.started {
                await progress.begin(total: hosts.count)
                if logging { print("[Ping] forcing progress.started=true (late start)") }
            }
            if current.total == 0 {
                if logging { print("[Ping][WARN] enqueue before progress total set (hosts=\(hosts.count))") }
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
        Task { [pingService] in
            if logging { print("[Ping] creating stream for host=\(host)") }
            let stream = await pingService.pingStream(config: PingConfig(host: host, count: baseConfig.count, interval: baseConfig.interval, timeoutPerPing: baseConfig.timeoutPerPing))
            var sawSuccess = false
            var measurementCount = 0
            for await m in stream {
                measurementCount += 1
                if logging { print("[Ping] measurement \(measurementCount) for host=\(host): \(m.status)") }
                if case .success = m.status { sawSuccess = true }
                await storeRef.applyPing(m)
            }
            if logging { print("[Ping] stream complete host=\(host) sawSuccess=\(sawSuccess) measurements=\(measurementCount)") }
            await self.didFinish(host: host, sawSuccess: sawSuccess)
            if let progressRef, sawSuccess { await progressRef.incrementSuccess() }
        }
    }

    private func didFinish(host: String, sawSuccess: Bool) async {
        let logging = (ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1")
        active.remove(host)
        if let progress = progress {
            let current = await progress.getCurrentProgress()
            await progress.incrementCompleted()
            let newCompleted = current.completed + 1
            if logging { print("[Ping] didFinish host=\(host) completed=\(newCompleted)/\(current.total) success=\(sawSuccess) (was \(current.completed))") }
            if current.total == 0 {
                if logging { print("[Ping][WARN] progress.totalHosts still 0 at didFinish (race condition)") }
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
    private let arpService: ARPService
    private var tasks: [Task<Void, Never>] = []
    private var started = false

    init(store: DeviceSnapshotStore, pingOrchestrator: PingOrchestrator, providers: [DiscoveryProvider], hostEnumerator: HostEnumerator = LocalSubnetEnumerator(), arpService: ARPService = ARPService()) {
        self.store = store
        self.pingOrchestrator = pingOrchestrator
        self.providers = providers
        self.hostEnumerator = hostEnumerator
        self.arpService = arpService
    }

    func start(pingHosts: [String], pingConfig: PingConfig, mdnsWarmupSeconds: Double = 2.0, autoEnumerateIfEmpty: Bool = true, maxAutoEnumeratedHosts: Int = 256) {
        guard !started else { return }
        started = true
        for provider in providers {
            let stream = provider.start()
            let t = Task {
                for await dev in stream {
                    await self.store.upsert(dev, source: .mdns)
                }
            }
            tasks.append(t)
        }
        Task { [pingHosts, pingConfig, autoEnumerateIfEmpty, maxAutoEnumeratedHosts] in
            try? await Task.sleep(nanoseconds: UInt64(mdnsWarmupSeconds * 1_000_000_000))
            let hosts: [String]
            if pingHosts.isEmpty, autoEnumerateIfEmpty {
                let enumerated = hostEnumerator.enumerate(maxHosts: maxAutoEnumeratedHosts)
                hosts = enumerated.isEmpty ? [] : enumerated
                if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
                    print("[Discovery] auto-enumerated hosts count=\(hosts.count)")
                }
            } else {
                hosts = pingHosts
            }
            if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
                print("[Discovery] starting ping batch size=\(hosts.count)")
            }
            if let progress = await self.pingOrchestrator.currentProgress() {
                if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
                    print("[Discovery] calling progress.begin total=\(hosts.count)")
                }
                await progress.begin(total: hosts.count)
                let current = await progress.getCurrentProgress()
                if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
                    print("[Discovery] progress after begin total=\(current.total) started=\(current.started)")
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
                var current = await progress.getCurrentProgress()
                while !current.finished {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    current = await progress.getCurrentProgress()
                }
            }

            // Read ARP table to get MAC addresses
            if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
                print("[Discovery] reading ARP table")
            }

#if os(macOS)
            if !hosts.isEmpty {
                await self.arpService.populateCache(for: hosts)
            }
#endif

            let ipToMac = await self.arpService.getMACAddresses(for: Set(hosts), delaySeconds: 0.2)

            // Update devices with MAC addresses
            if !ipToMac.isEmpty {
                for (ip, mac) in ipToMac {
                    if let existingDevice = await MainActor.run(body: { self.store.devices.first(where: { $0.primaryIP == ip || $0.ips.contains(ip) }) }) {
                        var updatedDevice = existingDevice
                        if (updatedDevice.macAddress ?? "").isEmpty {
                            updatedDevice.macAddress = mac
                        }
                        if !updatedDevice.discoverySources.contains(.arp) {
                            updatedDevice.discoverySources.insert(.arp)
                        }
                        await self.store.upsert(updatedDevice, source: .arp)
                        if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
                            print("[Discovery] ARP merged host=\(ip) mac=\(mac ?? "")")
                        }
                    }
                }
            }

            // Create placeholder devices for any hosts that are still missing after ARP lookup
            for host in hosts {
                guard let mac = ipToMac[host] else { continue }
                let exists = await MainActor.run { self.store.devices.contains(where: { $0.primaryIP == host || $0.ips.contains(host) }) }
                if !exists {
                    var device = Device(primaryIP: host,
                                        ips: [host],
                                        macAddress: mac,
                                        discoverySources: [.arp],
                                        firstSeen: Date(),
                                        lastSeen: Date())
                    await self.store.upsert(device, source: .arp)
                    if ProcessInfo.processInfo.environment["PING_INFO_LOG"] == "1" {
                        print("[Discovery] created ARP-derived device host=\(host) mac=\(mac ?? "")")
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
