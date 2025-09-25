import XCTest
@testable import UnifiedScanner

@MainActor final class DiscoveryCoordinatorTests: XCTestCase {
    func testCoordinatorStagesMDNSBeforePingAndCreatesDeviceOnFirstSuccessfulPing() async {
        let environment = AppEnvironment(deviceMutationBus: DeviceMutationBus())
        let store = SnapshotService(persistenceKey: "coord-test", persistence: MemoryPersistence(), classification: ClassificationService.self, mutationBus: environment.deviceMutationBus)
        let providerDevice = Device(primaryIP: "192.168.1.10", ips: ["192.168.1.10"], hostname: "apple-tv.local", discoverySources: [.mdns])
        let provider = TestProvider(devices: [providerDevice], perDeviceDelay: 0.05)
        let mockPingService = OneShotMockPingService(rtt: 7.0)
        let bus = environment.deviceMutationBus
        let orchestrator = PingOrchestrator(pingService: mockPingService, mutationBus: bus, maxConcurrent: 4)
        let coordinator = DiscoveryCoordinator(store: store, pingOrchestrator: orchestrator, mutationBus: bus, providers: [provider])

        // Collect change events until ping device
        var changes: [DeviceChange] = []
        let stream = store.mutationStream(includeInitialSnapshot: false)
        let collectTask = Task {
            for await m in stream {
                if case .change(let change) = m {
                    changes.append(change)
                    if change.after.primaryIP == "192.168.1.99" && change.source == .ping { break }
                }
            }
        }

        await coordinator.startBonjour()
        await coordinator.startScan(pingHosts: ["192.168.1.99"], pingConfig: PingConfig(host: "unused", count: 1, interval: 0.1, timeoutPerPing: 0.1), mdnsWarmupSeconds: 0.1, autoEnumerateIfEmpty: false, maxAutoEnumeratedHosts: 0)

        try? await Task.sleep(nanoseconds: 800_000_000)
        collectTask.cancel()

        XCTAssertTrue(changes.count >= 2, "Expected at least two change events")
        // Find the mdns and ping changes
        let mdnsChange = changes.first { $0.source == .mdns && $0.after.primaryIP == "192.168.1.10" }
        let pingChange = changes.first { $0.source == .ping && $0.after.primaryIP == "192.168.1.99" }
        XCTAssertNotNil(mdnsChange, "mDNS change should be present")
        XCTAssertNotNil(pingChange, "Ping change should be present")
        XCTAssertTrue(pingChange?.changed.contains(.rttMillis) == true, "Ping change should include RTT")

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

    private actor CancelState {
        var cancelled = false
        func cancel() { cancelled = true }
    }
    private let state = CancelState()

    init(devices: [Device], perDeviceDelay: TimeInterval) {
        self.devices = devices
        self.perDeviceDelay = perDeviceDelay
    }

    func start(mutationBus: DeviceMutationBus) -> AsyncStream<DeviceMutation> {
        AsyncStream { continuation in
            Task {
                for dev in devices {
                    if await state.cancelled || Task.isCancelled { break }
                    let mutation = DeviceMutation.change(DeviceChange(before: nil, after: dev, changed: Set(DeviceField.allCases), source: .mdns))
                    continuation.yield(mutation)
                    try? await Task.sleep(nanoseconds: UInt64(perDeviceDelay * 1_000_000_000))
                }
                continuation.finish()
            }
        }
    }

    func stop() {
        Task { await state.cancel() }
    }
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
