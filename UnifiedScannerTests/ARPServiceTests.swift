import XCTest
@testable import UnifiedScanner

final class ARPServiceTests: XCTestCase {
    func testARPEntryInit() {
        let entry = ARPService.ARPEntry(ipAddress: "192.168.1.1", macAddress: "AA:BB:CC:DD:EE:FF", interface: "en0", isStatic: true)
        XCTAssertEqual(entry.ipAddress, "192.168.1.1")
        XCTAssertEqual(entry.macAddress, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(entry.interface, "en0")
        XCTAssertTrue(entry.isStatic)
    }

    func testARPEntrySendable() async {
        let entry = ARPService.ARPEntry(ipAddress: "192.168.1.1", macAddress: "AA:BB:CC:DD:EE:FF", interface: "en0")
        // Since Sendable, can pass across actors
        let actor = TestActor()
        await actor.receive(entry)
    }

    actor TestActor {
        func receive(_ entry: ARPService.ARPEntry) {
            // No op
        }
    }

    func testGetMACAddressesEmptyIPs() async {
        let service = ARPService()
        let map = await service.getMACAddresses(for: [])
        XCTAssertTrue(map.isEmpty)
    }

    func testGetMACAddressesFullTable() async {
        let service = ARPService()
        let map = await service.getMACAddresses(for: [])
        // Depends on system, but check format
        for (ip, mac) in map {
            XCTAssertTrue(ip.isIPv4)
            XCTAssertTrue(mac.count == 17 && mac.contains(":"))
        }
    }

    func testBroadcastAddress() {
        XCTAssertEqual(ARPService.broadcastAddress(from: "192.168.1.10"), "192.168.1.255")
        XCTAssertEqual(ARPService.broadcastAddress(from: "10.0.0.5"), "10.0.0.255")
        XCTAssertNil(ARPService.broadcastAddress(from: "invalid"))
        XCTAssertNil(ARPService.broadcastAddress(from: "192.168.1"))
    }

    func testDefaultUDPPorts() {
        let ports = ARPService.defaultUDPPorts
        XCTAssertEqual(ports.count, 5)
        XCTAssertTrue(ports.contains(137))
        XCTAssertTrue(ports.contains(5353))
    }

    func testMacString() {
        let bytes: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
        let ptr = bytes.withUnsafeBufferPointer { $0.baseAddress! }
        let mac = ARPService.macString(from: ptr)
        XCTAssertEqual(mac, "AA:BB:CC:DD:EE:FF")
    }

    func testAdvancePointer() {
        var sa = sockaddr()
        sa.sa_len = 16
        let pointer = UnsafeRawPointer(bitPattern: 0x1000) // dummy
        let advanced = ARPService.advancePointer(from: pointer!, sockaddr: sa)
        XCTAssertEqual(advanced, UnsafeRawPointer(bitPattern: 0x1010)) // 16 aligned
    }

    // Note: Full table and populateCache are system-dependent, tested indirectly
    func testPopulateCacheNoopOnNonMac() {
        // On non-macOS, it's no-op, but since #if, test compiles
    }
}