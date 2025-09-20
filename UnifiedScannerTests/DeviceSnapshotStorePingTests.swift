import XCTest
@testable import UnifiedScanner

final class DeviceSnapshotStorePingTests: XCTestCase {
    func testApplyPingUpdatesRTTAndLastSeen() async {
        let persistence = EphemeralPersistencePing()
        let store = await MainActor.run { DeviceSnapshotStore(persistenceKey: "test", persistence: persistence, classification: ClassificationService.self) }
        let initial = Device(primaryIP: "192.168.1.10", ips: ["192.168.1.10"], hostname: "test-host", discoverySources: [.mdns])
        await store.upsert(initial)
        let before = await MainActor.run { store.devices.first(where: { $0.primaryIP == "192.168.1.10" })! }
        XCTAssertNil(before.rttMillis)
        let measure = PingMeasurement(host: "192.168.1.10", sequence: 0, status: .success(rttMillis: 12.5))
        await store.applyPing(measure)
        let after = await MainActor.run { store.devices.first(where: { $0.primaryIP == "192.168.1.10" })! }
        XCTAssertEqual(after.rttMillis, 12.5)
        XCTAssertTrue(after.discoverySources.contains(.ping))
        XCTAssertNotNil(after.lastSeen)
    }

    func testApplyPingTimeoutDoesNotChangeLastSeenOrRTT() async {
        let persistence = EphemeralPersistencePing()
        let store = await MainActor.run { DeviceSnapshotStore(persistenceKey: "test2", persistence: persistence, classification: ClassificationService.self) }
        let initial = Device(primaryIP: "192.168.1.11", ips: ["192.168.1.11"], hostname: "test-host2", discoverySources: [.mdns])
        await store.upsert(initial)
        let before = await MainActor.run { store.devices.first(where: { $0.primaryIP == "192.168.1.11" })! }
        let beforeLastSeen = before.lastSeen
        let measure = PingMeasurement(host: "192.168.1.11", sequence: 0, status: .timeout)
        await store.applyPing(measure)
        let after = await MainActor.run { store.devices.first(where: { $0.primaryIP == "192.168.1.11" })! }
        XCTAssertNil(after.rttMillis)
        XCTAssertEqual(after.lastSeen, beforeLastSeen)
        XCTAssertFalse(after.discoverySources.contains(.ping))
    }
}

// Ephemeral non-persisting adapter for tests
private struct EphemeralPersistencePing: DevicePersistence {
    var memory: [Device] = []
    func load(key: String) -> [Device] { memory }
    func save(_ devices: [Device], key: String) {}
}
