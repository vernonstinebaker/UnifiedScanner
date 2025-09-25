import XCTest
@testable import UnifiedScanner

final class PingOrchestratorTests: XCTestCase {
    func testMockPingServiceWorks() async {
        let mockPingService = MockPingService()
        let config = PingConfig(host: "10.0.0.99")
        
        let stream = await mockPingService.pingStream(config: config)
        var measurements: [PingMeasurement] = []
        
        for await measurement in stream {
            measurements.append(measurement)
        }
        
        XCTAssertEqual(measurements.count, 1)
        XCTAssertEqual(measurements[0].host, "10.0.0.99")
        if case .success(let rtt) = measurements[0].status {
            XCTAssertEqual(rtt, 5.0)
        } else {
            XCTFail("Expected success status")
        }
    }
    
    func testEnqueuePingsUpdatesStore() async {
        let persistence = EphemeralPersistencePO()
        let testBus = await MainActor.run { DeviceMutationBus() }
        let store = await MainActor.run {
            SnapshotService(persistenceKey: "ping-orch",
                            persistence: persistence,
                            classification: ClassificationService.self,
                            mutationPublisher: DeviceMutationBusPublisher(bus: testBus))
        }
        
        await store.upsert(Device(primaryIP: "192.168.1.200", ips: ["192.168.1.200"], hostname: "h1", discoverySources: [.mdns]))
        await store.upsert(Device(primaryIP: "192.168.1.201", ips: ["192.168.1.201"], hostname: "h2", discoverySources: [.mdns]))
        
        let mockPingService = MockPingService()
        let orchestrator = PingOrchestrator(pingService: mockPingService, mutationBus: testBus, maxConcurrent: 2)
        
        await orchestrator.enqueue(hosts: ["192.168.1.200", "192.168.1.201"], config: PingConfig(host: "placeholder"))
        
        // Allow async tasks to run
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        let devs = await MainActor.run { store.devices }
        
        let d1 = devs.first { $0.primaryIP == "192.168.1.200" }
        let d2 = devs.first { $0.primaryIP == "192.168.1.201" }
        
        XCTAssertNotNil(d1, "Device 192.168.1.200 should exist")
        XCTAssertNotNil(d2, "Device 192.168.1.201 should exist")
        
        if let d1 = d1, let d2 = d2 {
            XCTAssertNotNil(d1.rttMillis)
            XCTAssertNotNil(d2.rttMillis)
        }
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
