import XCTest
@testable import UnifiedScanner

@MainActor final class DiscoveryCoordinatorTests: XCTestCase {
    func testCoordinatorStagesMDNSBeforePingAndCreatesDeviceOnFirstSuccessfulPing() async {
        let store = DeviceSnapshotStore(persistenceKey: "coord-test", persistence: MemoryPersistence(), classification: ClassificationService.self)
        let providerDevice = Device(primaryIP: "192.168.1.10", ips: ["192.168.1.10"], hostname: "apple-tv.local", discoverySources: [.mdns])
        let provider = TestProvider(devices: [providerDevice], perDeviceDelay: 0.05)
        let mockPingService = OneShotMockPingService(rtt: 7.0)
        let orchestrator = PingOrchestrator(pingService: mockPingService, store: store, maxConcurrent: 4)
        let coordinator = DiscoveryCoordinator(store: store, pingOrchestrator: orchestrator, providers: [provider])

        // Collect first two change events (mdns upsert, ping device creation with RTT)
        var changes: [DeviceChange] = []
        let stream = store.mutationStream(includeInitialSnapshot: false)
        let collectTask = Task {
            for await m in stream {
                if case .change(let change) = m {
                    changes.append(change)
                    if changes.count >= 2 { break }
                }
            }
        }

        await coordinator.start(pingHosts: ["192.168.1.99"], pingConfig: PingConfig(host: "unused", count: 1, interval: 0.1, timeoutPerPing: 0.1), mdnsWarmupSeconds: 0.1)

        try? await Task.sleep(nanoseconds: 800_000_000)
        collectTask.cancel()

        XCTAssertEqual(changes.count, 2, "Expected exactly two change events")
        XCTAssertEqual(changes.first?.source, .mdns, "First change should originate from mdns provider")
        XCTAssertTrue(changes.last.map { $0.after.primaryIP == "192.168.1.99" && $0.source == .ping && $0.changed.contains(.rttMillis) } ?? false, "Second change should be ping device with RTT")

        let devices = store.devices
        let mdnsDevice = devices.first { $0.primaryIP == "192.168.1.10" }
        let pingDevice = devices.first { $0.primaryIP == "192.168.1.99" }
        XCTAssertNotNil(mdnsDevice, "mDNS device missing")
        XCTAssertNotNil(pingDevice, "Ping device missing")
        XCTAssertTrue(mdnsDevice?.discoverySources.contains(.mdns) == true)
        XCTAssertTrue(pingDevice?.discoverySources.contains(.ping) == true)
        XCTAssertNotNil(pingDevice?.rttMillis, "Ping device should have RTT after measurement")
    }
}

// MARK: - Mocks
struct MemoryPersistence: DevicePersistence {
    func load(key: String) -> [Device] { [] }
    func save(_ devices: [Device], key: String) { }
}

final class TestProvider: DiscoveryProvider {
    let name = "test-mdns"
    private let devices: [Device]
    private let perDeviceDelay: TimeInterval
    private var cancelled = false
    init(devices: [Device], perDeviceDelay: TimeInterval) { self.devices = devices; self.perDeviceDelay = perDeviceDelay }
    func start() -> AsyncStream<Device> {
        cancelled = false
        return AsyncStream { continuation in
            Task {
                for dev in devices {
                    if cancelled || Task.isCancelled { break }
                    continuation.yield(dev)
                    try? await Task.sleep(nanoseconds: UInt64(perDeviceDelay * 1_000_000_000))
                }
                continuation.finish()
            }
        }
    }
    func stop() { cancelled = true }
}

struct OneShotMockPingService: PingService {
    let rtt: Double
    func pingStream(config: PingConfig) async -> AsyncStream<PingMeasurement> {
        AsyncStream { continuation in
            Task {
                // Simulate immediate success
                continuation.yield(PingMeasurement(host: config.host, sequence: 0, status: .success(rttMillis: rtt)))
                continuation.finish()
            }
        }
    }
}
