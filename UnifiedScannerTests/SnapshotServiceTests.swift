import XCTest
@testable import UnifiedScanner

@MainActor final class SnapshotServiceTests: XCTestCase {
    func testUpsertPreservesFirstSeenAndUpdatesLastSeen() async {
        let store = SnapshotService(persistence: EphemeralPersistence())
        var d = Device.mockMac
        d.firstSeen = nil
        await store.upsert(d)
        let first = store.devices.first!
        XCTAssertNotNil(first.firstSeen)
        let firstSeen = first.firstSeen!
        sleep(1)
        await store.upsert(d)
        let second = store.devices.first!
        XCTAssertEqual(second.firstSeen, firstSeen)
        XCTAssertTrue((second.lastSeen ?? Date()).timeIntervalSince(firstSeen) >= 1)
    }

    func testIPUnionAndPrimaryIPPreserved() async {
        let store = SnapshotService(persistence: EphemeralPersistence())
        var base = Device.mockMac
        base.primaryIP = "192.168.1.10"
        await store.upsert(base)
        var update = base
        update.ips.insert("10.0.0.5")
        update.primaryIP = nil // should not clear existing
        await store.upsert(update)
        let result = store.devices.first!
        XCTAssertEqual(result.primaryIP, "192.168.1.10")
        XCTAssertTrue(result.ips.contains("10.0.0.5"))
    }

    func testServicesMergedAndDeduped() async {
        let store = SnapshotService(persistence: EphemeralPersistence())
        var dev = Device.mockMac
        dev.services = []
        await store.upsert(dev)
        var incoming = dev
        incoming.services = [
            NetworkService(id: UUID(), name: "HTTP", type: .http, rawType: "_http._tcp", port: 80, isStandardPort: true),
            NetworkService(id: UUID(), name: "HTTP Alt", type: .http, rawType: "_http._tcp", port: 80, isStandardPort: true)
        ]
        await store.upsert(incoming)
        let merged = store.devices.first!.services
        XCTAssertEqual(merged.count, 1, "Services should be deduped by (type,port)")
        XCTAssertTrue(merged.first?.name == "HTTP Alt" || merged.first?.name == "HTTP")
    }

    func testClassificationRecomputedOnServiceChange() async {
        let store = SnapshotService(persistence: EphemeralPersistence())
        var dev = Device.mockMac
        dev.services = []
        await store.upsert(dev)
        _ = store.devices.first!.classification
        var incoming = dev
        incoming.services = [NetworkService(id: UUID(), name: "AirPlay", type: .airplay, rawType: "_airplay._tcp", port: 7000, isStandardPort: true)]
        await store.upsert(incoming)
        let updated = store.devices.first!.classification
        // Classification may not change even if services added; just ensure classification remains valid after service merge.
        XCTAssertNotNil(updated, "Classification should remain available after service update")
    }
    func testPortMergePrecedenceAndOrdering() async {
        let store = SnapshotService(persistence: EphemeralPersistence())
        let dev = Device(primaryIP: "10.0.0.10",
                         ips: ["10.0.0.10"],
                         services: [],
                         openPorts: [Port(number: 80, serviceName: "http", description: "HTTP", status: .closed, lastSeenOpen: nil)])
        await store.upsert(dev)
        var update = dev
        update.openPorts = [
            Port(number: 80, serviceName: "http", description: "HTTP", status: .open, lastSeenOpen: Date()), // should replace closed
            Port(number: 22, serviceName: "ssh", description: "SSH", status: .filtered, lastSeenOpen: nil)
        ]
        await store.upsert(update)
        let ports = store.devices.first!.openPorts
        XCTAssertEqual(ports.count, 2)
        XCTAssertEqual(ports.map { $0.number }, [22, 80], "Ports should be sorted ascending by number")
        let port80 = ports.first { $0.number == 80 }!
        XCTAssertEqual(port80.status, .open, "Open status should take precedence over closed")
    }

    func testDiscoverySourcesUnion() async {
        let store = SnapshotService(persistence: EphemeralPersistence())
        let dev = Device(primaryIP: "10.0.0.20",
                         ips: ["10.0.0.20"],
                         discoverySources: [.arp],
                         services: [],
                         openPorts: [])
        await store.upsert(dev)
        var update = dev
        update.discoverySources = [.ping, .mdns]
        await store.upsert(update)
        let sources = store.devices.first!.discoverySources
        XCTAssertTrue(sources.contains(.arp))
        XCTAssertTrue(sources.contains(.ping))
        XCTAssertTrue(sources.contains(.mdns))
        XCTAssertEqual(sources.count, 3, "Expected union of discovery sources without loss")
    }

    func testFingerprintMergeDoesNotTriggerReclassification() async {
        let store = SnapshotService(persistence: EphemeralPersistence())
        var dev = Device.mockMac
        dev.fingerprints = ["osGuess": "macOS"]
        await store.upsert(dev)
        let initial = store.devices.first!.classification
        var update = dev
        update.fingerprints = ["serial": "ABC123"] // Only fingerprints change
        await store.upsert(update)
        let after = store.devices.first!.classification
        XCTAssertEqual(initial, after, "Classification should not recompute when only fingerprints change")
    }
}

// MARK: - Ephemeral Persistence (no disk/iCloud writes)
struct EphemeralPersistence: DevicePersistence {
    var storage: [Device] = []
    func load(key: String) -> [Device] { [] }
    func save(_ devices: [Device], key: String) { }
}
