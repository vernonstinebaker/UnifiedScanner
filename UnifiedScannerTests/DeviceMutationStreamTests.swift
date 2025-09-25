import XCTest
@testable import UnifiedScanner

@MainActor final class DeviceMutationStreamTests: XCTestCase {
    func testStreamEmitsInitialSnapshotAndChangeOnUpsert() async {
        let testBus = DeviceMutationBus()
        let store = SnapshotService(persistence: EphemeralPersistenceDM(), mutationBus: testBus)
        var events: [DeviceMutation] = []
        let stream = store.mutationStream()
        let collectTask = Task { for await e in stream.prefix(2) { events.append(e) } }
        let dev = Device(primaryIP: "192.168.1.200", ips: ["192.168.1.200"], hostname: "h1", discoverySources: [.mdns])
        await store.upsert(dev)
        _ = await collectTask.value
        XCTAssertEqual(events.count, 2)
        guard case .snapshot(let snapDevices) = events[0] else { return XCTFail("First event should be snapshot") }
        XCTAssertTrue(snapDevices.isEmpty)
        guard case .change(let change) = events[1] else { return XCTFail("Second event should be change") }
        XCTAssertNil(change.before)
        XCTAssertEqual(change.after.primaryIP, "192.168.1.200")
        XCTAssertTrue(change.changed.contains(.primaryIP))
        XCTAssertTrue(change.changed.contains(.ips))
    }

    func testPingEmitsChangeWithRTTField() async {
        let testBus = DeviceMutationBus()
        let store = SnapshotService(persistence: EphemeralPersistenceDM(), mutationBus: testBus)
        let dev = Device(primaryIP: "192.168.1.201", ips: ["192.168.1.201"], hostname: "pinger", discoverySources: [.mdns])
        await store.upsert(dev)
        var rttEvent: DeviceChange?
        let stream = store.mutationStream(includeInitialSnapshot: false)
        let collectTask = Task {
            for await e in stream.prefix(1) {
                if case .change(let change) = e, change.changed.contains(.rttMillis) { rttEvent = change }
            }
        }
        let measurement = PingMeasurement(host: "192.168.1.201", sequence: 0, status: .success(rttMillis: 5.0))
        await store.applyPing(measurement)
        _ = await collectTask.value
        XCTAssertNotNil(rttEvent, "Expected RTT change event")
        XCTAssertEqual(rttEvent?.after.rttMillis, 5.0)
    }

    func testClassificationChangeEmitsClassificationField() async {
        let testBus = DeviceMutationBus()
        let store = SnapshotService(persistence: EphemeralPersistenceDM(), mutationBus: testBus)
        let stream = store.mutationStream(includeInitialSnapshot: false)
        var events: [DeviceMutation] = []
        let collectTask = Task { for await e in stream.prefix(2) { events.append(e) } }
        // Initial device: minimal info -> unknown classification
        let base = Device(primaryIP: "192.168.1.202", ips: ["192.168.1.202"], hostname: nil, discoverySources: [])
        await store.upsert(base)
        // Second upsert adds SSH service triggering classification rule (ssh_only)
        let sshService = NetworkService(name: "ssh", type: .ssh, rawType: "_ssh._tcp", port: 22, isStandardPort: true)
        let updated = Device(id: base.id, primaryIP: base.primaryIP, ips: base.ips, hostname: base.hostname, vendor: nil, discoverySources: [], services: [sshService])
        await store.upsert(updated)
        _ = await collectTask.value
        XCTAssertEqual(events.count, 2)
        guard case .change(let secondChange) = events[1] else { return XCTFail("Expected second event to be change") }
        XCTAssertTrue(secondChange.changed.contains(.classification), "Expected classification in changed fields")
        let beforeRaw = secondChange.before?.classification?.rawType
        let afterRaw = secondChange.after.classification?.rawType
        XCTAssertNotEqual(beforeRaw, afterRaw, "Raw type should change after adding ssh service")
        XCTAssertEqual(afterRaw, "ssh_only")
    }

    func testRemoveAllEmitsSnapshotEmpty() async {
        let testBus = DeviceMutationBus()
        let store = SnapshotService(persistence: EphemeralPersistenceDM(), mutationBus: testBus)
        let stream = store.mutationStream(includeInitialSnapshot: false)
        var events: [DeviceMutation] = []
        let collectTask = Task { for await e in stream.prefix(2) { events.append(e) } }
        let dev = Device(primaryIP: "192.168.1.203", ips: ["192.168.1.203"], hostname: "temp", discoverySources: [])
        await store.upsert(dev)
        store.removeAll()
        _ = await collectTask.value
        XCTAssertEqual(events.count, 2)
        guard case .snapshot(let empty) = events[1] else { return XCTFail("Expected second event to be snapshot") }
        XCTAssertTrue(empty.isEmpty)
    }


}

 

// MARK: - Ephemeral Persistence
struct EphemeralPersistenceDM: DevicePersistence {
    func load(key: String) -> [Device] { [] }
    func save(_ devices: [Device], key: String) { }
}
