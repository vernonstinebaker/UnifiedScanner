import XCTest
@testable import UnifiedScanner

final class PingOrchestratorSuccessCreationTests: XCTestCase {
    func testSuccessCreatesDevice() async {
        let persistence = EphemeralPersistencePOS()
        let store = await MainActor.run { SnapshotService(persistenceKey: "ping-orch-success", persistence: persistence, classification: ClassificationService.self) }
        // Ensure store initially empty
        let initialCount = await MainActor.run { store.devices.count }
        XCTAssertEqual(initialCount, 0)
        // Mock ping service that emits a single success with RTT
        let mock = SuccessOnlyPingService()
        await MainActor.run { DeviceMutationBus.shared.clearBuffer() }
        let orchestrator = PingOrchestrator(pingService: mock, mutationBus: DeviceMutationBus.shared, maxConcurrent: 1)
        await orchestrator.enqueue(hosts: ["10.0.0.201"], config: PingConfig(host: "placeholder", count: 1, interval: 0.01, timeoutPerPing: 0.05))
        try? await Task.sleep(nanoseconds: 400_000_000)
        let devices = await MainActor.run { store.devices }
        // Device should be created because ping succeeded
        XCTAssertTrue(devices.contains { $0.primaryIP == "10.0.0.201" && $0.rttMillis != nil })
    }
}

private struct SuccessOnlyPingService: PingService {
    func pingStream(config: PingConfig) async -> AsyncStream<PingMeasurement> {
        AsyncStream { continuation in
            Task {
                continuation.yield(PingMeasurement(host: config.host, sequence: 0, status: .success(rttMillis: 3.2)))
                continuation.finish()
            }
        }
    }
}

private struct EphemeralPersistencePOS: DevicePersistence {
    var memory: [Device] = []
    func load(key: String) -> [Device] { memory }
    func save(_ devices: [Device], key: String) {}
}
