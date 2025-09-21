import XCTest
@testable import UnifiedScanner

final class PingOrchestratorTests: XCTestCase {
    func testEnqueuePingsUpdatesStore() async {
        let persistence = EphemeralPersistencePO()
        let store = await MainActor.run { SnapshotService(persistenceKey: "ping-orch", persistence: persistence, classification: ClassificationService.self) }
        await store.upsert(Device(primaryIP: "10.0.0.2", ips: ["10.0.0.2"], hostname: "h1", discoverySources: [.mdns]))
        await store.upsert(Device(primaryIP: "10.0.0.3", ips: ["10.0.0.3"], hostname: "h2", discoverySources: [.mdns]))
        let mockPingService = MockPingService()
        let bus = await MainActor.run { DeviceMutationBus.shared }
        let orchestrator = PingOrchestrator(pingService: mockPingService, mutationBus: bus, maxConcurrent: 2)
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

private struct MockPingService: PingService {
    func pingStream(config: PingConfig) async -> AsyncStream<PingMeasurement> {
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
