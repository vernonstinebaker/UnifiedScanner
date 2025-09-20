import XCTest
@testable import UnifiedScanner

@MainActor final class AutoEnumerationTests: XCTestCase {
    func testAutoEnumerationUsesHostEnumeratorWhenPingHostsEmpty() async {
        // Arrange
        let store = SnapshotService(persistenceKey: "auto-enum", persistence: MemoryPersistenceAE(), classification: ClassificationService.self)
        let mockEnumerator = MockEnumerator(hosts: ["10.0.0.5", "10.0.0.6"]) // deterministic
        let mockPingService = OneShotMockPingServiceAE(rtt: 3.3)
        let orchestrator = PingOrchestrator(pingService: mockPingService, store: store, maxConcurrent: 4)
        let coordinator = DiscoveryCoordinator(store: store, pingOrchestrator: orchestrator, providers: [], hostEnumerator: mockEnumerator)

        var yieldedHosts: Set<String> = []
        let stream = store.mutationStream(includeInitialSnapshot: false)
        let collectTask = Task {
            for await m in stream {
                if case .change(let change) = m {
                    yieldedHosts.insert(change.after.primaryIP ?? "")
                    if yieldedHosts.count >= 2 { break }
                }
            }
        }

        // Act
        await coordinator.startAndWait(pingHosts: [], pingConfig: PingConfig(host: "placeholder", count: 1, interval: 0.05, timeoutPerPing: 0.05), mdnsWarmupSeconds: 0.001, autoEnumerateIfEmpty: true, maxAutoEnumeratedHosts: 10)
        // Wait up to 2 seconds for both hosts instead of fixed sleep
        let start = Date()
        while yieldedHosts.count < 2 && Date().timeIntervalSince(start) < 2.0 {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        collectTask.cancel()

        // Assert
        XCTAssertTrue(yieldedHosts.contains("10.0.0.5"))
        XCTAssertTrue(yieldedHosts.contains("10.0.0.6"))
        let devs = store.devices
        XCTAssertNotNil(devs.first { $0.primaryIP == "10.0.0.5" })
        XCTAssertNotNil(devs.first { $0.primaryIP == "10.0.0.6" })
    }
}

private struct MockEnumerator: HostEnumerator {
    let hosts: [String]
    func enumerate(maxHosts: Int?) -> [String] { return hosts }
}

private struct MemoryPersistenceAE: DevicePersistence {
    func load(key: String) -> [Device] { [] }
    func save(_ devices: [Device], key: String) { }
}

private struct OneShotMockPingServiceAE: PingService {
    let rtt: Double
    func pingStream(config: PingConfig) async -> AsyncStream<PingMeasurement> {
        AsyncStream { continuation in
            Task {
                continuation.yield(PingMeasurement(host: config.host, sequence: 0, status: .success(rttMillis: rtt)))
                continuation.finish()
            }
        }
    }
}
