import Foundation

public protocol DiscoveryProvider: Sendable {
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

    init(pinger: Pinger, store: DeviceSnapshotStore, maxConcurrent: Int = 32) {
        self.pinger = pinger
        self.store = store
        self.maxConcurrent = maxConcurrent
    }

    public func enqueue(hosts: [String], config: PingConfig) {
        Task { [hosts, config] in
            for host in hosts {
                // throttle
                while await self.active.count >= self.maxConcurrent {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                await self.launch(host: host, baseConfig: config)
            }
        }
    }

    private func launch(host: String, baseConfig: PingConfig) {
        active.insert(host)
        let storeRef = store
        Task { [pinger] in
            let stream = await pinger.pingStream(config: PingConfig(host: host, count: baseConfig.count, interval: baseConfig.interval, timeoutPerPing: baseConfig.timeoutPerPing))
            for await m in stream {
                await MainActor.run { storeRef.applyPing(m) }
            }
            await self.didFinish(host: host)
        }
    }

    private func didFinish(host: String) {
        active.remove(host)
    }
}
