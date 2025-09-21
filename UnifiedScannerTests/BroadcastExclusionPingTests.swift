import XCTest
@testable import UnifiedScanner

final class BroadcastExclusionPingTests: XCTestCase {
    func testSuccessfulPingToBroadcastIsIgnored() async {
        // Given a local /24 network 192.168.1.0/24, broadcast is 192.168.1.255.
        // We simulate a successful ping measurement to that address; SnapshotService should not create a device.
        let persistence = EphemeralPersistenceBroadcast()
        let store = await MainActor.run { SnapshotService(persistenceKey: "broadcast-test", persistence: persistence, classification: ClassificationService.self) }
        // Precondition: no devices yet
        let initialCount = await MainActor.run { store.devices.count }
        XCTAssertEqual(initialCount, 0)
        let measurement = PingMeasurement(host: "192.168.1.255", sequence: 0, status: .success(rttMillis: 5.0))
        await store.applyPing(measurement)
        // Expectation: still zero devices because broadcast should be filtered
        let finalCount = await MainActor.run { store.devices.count }
        XCTAssertEqual(finalCount, 0, "Broadcast address should not create a device on success ping")
    }
}

private struct EphemeralPersistenceBroadcast: DevicePersistence {
    var memory: [Device] = []
    func load(key: String) -> [Device] { memory }
    func save(_ devices: [Device], key: String) {}
}
