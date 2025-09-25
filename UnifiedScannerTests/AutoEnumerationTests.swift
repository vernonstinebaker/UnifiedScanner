import XCTest
@testable import UnifiedScanner

@MainActor final class AutoEnumerationTests: XCTestCase {
    func testAutoEnumerationUsesHostEnumeratorWhenPingHostsEmpty() async {
        // Arrange
        let testBus = DeviceMutationBus()
        let store = SnapshotService(persistenceKey: "auto-enum", persistence: MemoryPersistenceAE(), classification: ClassificationService.self, mutationBus: testBus)
        let mockEnumerator = MockEnumerator(hosts: ["192.168.1.200", "192.168.1.201"]) // deterministic
        let mockPingService = OneShotMockPingServiceAE(rtt: 3.3)
        let orchestrator = PingOrchestrator(pingService: mockPingService, mutationBus: testBus, maxConcurrent: 4)
        let coordinator = DiscoveryCoordinator(store: store, pingOrchestrator: orchestrator, mutationBus: testBus, providers: [], hostEnumerator: mockEnumerator)

        var yieldedHosts: Set<String> = []
        let stream = store.mutationStream(includeInitialSnapshot: false)
        let collectTask = Task {
            for await m in stream {
                switch m {
                case .ping(_):
                    break
                case .change(let change):
                    if change.source == .ping {
                        if let ip = change.after.primaryIP {
                            yieldedHosts.insert(ip)
                        }
                        if yieldedHosts.count >= 2 { 
                            break 
                        }
                    }
                case .snapshot(_):
                    break
                }
            }
        }

        // Act
        await coordinator.startScan(pingHosts: [], pingConfig: PingConfig(host: "placeholder", count: 1, interval: 0.05, timeoutPerPing: 0.05), mdnsWarmupSeconds: 0.001, autoEnumerateIfEmpty: true, maxAutoEnumeratedHosts: 10)
        
        // Give async ping tasks time to complete similar to PingOrchestratorTests
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Wait up to 5 seconds for both hosts instead of 2 seconds
        let start = Date()
        while yieldedHosts.count < 2 && Date().timeIntervalSince(start) < 5.0 {
            try? await Task.sleep(nanoseconds: 100_000_000) // Check every 100ms
        }
        collectTask.cancel()
        
        // Assert
        XCTAssertTrue(yieldedHosts.contains("192.168.1.200"))
        XCTAssertTrue(yieldedHosts.contains("192.168.1.201"))
        let devs = store.devices
        let pingDevice1 = devs.first { $0.primaryIP == "192.168.1.200" && $0.discoverySources.contains(.ping) }
        let pingDevice2 = devs.first { $0.primaryIP == "192.168.1.201" && $0.discoverySources.contains(.ping) }
        XCTAssertNotNil(pingDevice1, "Device 192.168.1.200 should exist and be ping-sourced")
        XCTAssertNotNil(pingDevice2, "Device 192.168.1.201 should exist and be ping-sourced")
    }
}

private struct MockEnumerator: HostEnumerator {
    let hosts: [String]
    func enumerate(maxHosts: Int?) -> [String] { 
        return hosts 
    }
}

private struct MemoryPersistenceAE: DevicePersistence {
    func load(key: String) -> [Device] { [] }
    func save(_ devices: [Device], key: String) { }
}

private struct OneShotMockPingServiceAE: PingService {
    let rtt: Double
    func pingStream(config: PingConfig) async -> AsyncStream<PingMeasurement> {
        return AsyncStream { continuation in
            Task {
                continuation.yield(PingMeasurement(host: config.host, sequence: 0, status: .success(rttMillis: rtt)))
                continuation.finish()
            }
        }
    }
}
