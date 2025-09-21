import XCTest
@testable import UnifiedScanner

final class PingOrchestratorTimeoutTests: XCTestCase {
    func testTimeoutDoesNotCreateDevice() async {
        let persistence = EphemeralPersistencePOT()
        let store = await MainActor.run { SnapshotService(persistenceKey: "ping-orch-timeout", persistence: persistence, classification: ClassificationService.self) }
        // Ensure store initially empty
        let initialCount = await MainActor.run { store.devices.count }
        XCTAssertEqual(initialCount, 0)
        // Mock ping service that only emits a timeout
        let mock = TimeoutOnlyPingService()
        // Fresh bus (shared) may contain buffered events; clear it
        await MainActor.run { DeviceMutationBus.shared.clearBuffer() }
        let orchestrator = PingOrchestrator(pingService: mock, mutationBus: DeviceMutationBus.shared, maxConcurrent: 1)
        await orchestrator.enqueue(hosts: ["10.0.0.200"], config: PingConfig(host: "placeholder", count: 1, interval: 0.01, timeoutPerPing: 0.01))
        try? await Task.sleep(nanoseconds: 400_000_000)
        let devices = await MainActor.run { store.devices }
        // No device should be created because ping never succeeded
        XCTAssertFalse(devices.contains { $0.primaryIP == "10.0.0.200" })
    }
}

private struct TimeoutOnlyPingService: PingService {
    func pingStream(config: PingConfig) async -> AsyncStream<PingMeasurement> {
        AsyncStream { continuation in
            Task {
                continuation.yield(PingMeasurement(host: config.host, sequence: 0, status: .timeout))
                continuation.finish()
            }
        }
    }
}

private struct EphemeralPersistencePOT: DevicePersistence {
    var memory: [Device] = []
    func load(key: String) -> [Device] { memory }
    func save(_ devices: [Device], key: String) {}
}
