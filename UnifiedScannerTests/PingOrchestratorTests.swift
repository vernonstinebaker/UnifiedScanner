import XCTest
@testable import UnifiedScanner

final class PingOrchestratorTests: XCTestCase {
    func testEnqueuePingsUpdatesStore() async {
        let persistence = EphemeralPersistencePO()
        let store = await MainActor.run { DeviceSnapshotStore(persistenceKey: "ping-orch", persistence: persistence, classification: ClassificationService.self) }
        await MainActor.run {
            store.upsert(Device(primaryIP: "10.0.0.2", ips: ["10.0.0.2"], hostname: "h1", discoverySources: [.mdns]))
            store.upsert(Device(primaryIP: "10.0.0.3", ips: ["10.0.0.3"], hostname: "h2", discoverySources: [.mdns]))
        }
        let mockPinger = MockPinger()
        let orchestrator = PingOrchestrator(pinger: mockPinger, store: store, maxConcurrent: 2)
        await orchestrator.enqueue(hosts: ["10.0.0.2", "10.0.0.3"], config: PingConfig(host: "placeholder"))
        // Allow async tasks to run
        try? await Task.sleep(nanoseconds: 500_000_000)
        let devs = await MainActor.run { store.devices }
        let d1 = devs.first { $0.primaryIP == "10.0.0.2" }!
        let d2 = devs.first { $0.primaryIP == "10.0.0.3" }!
        XCTAssertNotNil(d1.rttMillis)
        XCTAssertNotNil(d2.rttMillis)
    }
}

private struct MockPinger: Pinger {
    func pingStream(config: PingConfig) -> AsyncStream<PingMeasurement> {
        AsyncStream { continuation in
            Task {
                continuation.yield(PingMeasurement(host: config.host, sequence: 0, status: .success(rttMillis: 5.0)))
                continuation.finish()
            }
        }
    }
}

private struct EphemeralPersistencePO: DevicePersistence {
    var memory: [Device] = []
    func load(key: String) -> [Device] { memory }
    func save(_ devices: [Device], key: String) {}
}
