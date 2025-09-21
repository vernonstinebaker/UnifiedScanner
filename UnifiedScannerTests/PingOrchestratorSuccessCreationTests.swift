import XCTest
@testable import UnifiedScanner

@MainActor final class PingOrchestratorSuccessCreationTests: XCTestCase {
    func testSuccessCreatesDevice() async {
        let persistence = EphemeralPersistencePOS()
        let store = SnapshotService(persistenceKey: "ping-orch-success", persistence: persistence, classification: ClassificationService.self)
        // Ensure store initially empty
        XCTAssertEqual(store.devices.count, 0)
        // Mock ping service that emits a single success with RTT
        let mock = SuccessOnlyPingService()
        let bus = await MainActor.run { DeviceMutationBus.shared }
        await MainActor.run { bus.clearBuffer() }
        let orchestrator = PingOrchestrator(pingService: mock, mutationBus: bus, maxConcurrent: 1)
        await orchestrator.enqueue(hosts: ["10.0.0.201"], config: PingConfig(host: "placeholder", count: 1, interval: 0.01, timeoutPerPing: 0.05))
        try? await Task.sleep(nanoseconds: 400_000_000)
        let devices = store.devices
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
