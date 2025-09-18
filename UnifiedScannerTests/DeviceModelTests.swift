import XCTest
@testable import UnifiedScanner

final class DeviceModelTests: XCTestCase {
    func testIdentityPrefersMAC() {
        let d = Device(primaryIP: "192.168.0.10", hostname: "host", macAddress: "aa:bb:cc:00:11:22")
        XCTAssertEqual(d.id, "AA:BB:CC:00:11:22")
    }

    func testIdentityFallsBackToPrimaryIP() {
        let d = Device(primaryIP: "192.168.0.20", hostname: "host")
        XCTAssertEqual(d.id, "192.168.0.20")
    }

    func testBestDisplayIPPrefersPrivateIPv4() {
        let ips: Set<String> = ["8.8.8.8", "192.168.1.10"]
        XCTAssertEqual(IPHeuristics.bestDisplayIP(ips), "192.168.1.10")
    }

    func testOnlineDerivationUsesGraceInterval() {
        var d = Device(primaryIP: "192.168.0.3")
        XCTAssertFalse(d.isOnline)
        d.lastSeen = Date().addingTimeInterval(-100)
        XCTAssertTrue(d.isOnline)
    }

    func testServiceDedupIncludesPortDerived() {
        let svc = NetworkService(name: "SSH", type: .ssh, rawType: "_ssh._tcp", port: 22, isStandardPort: true)
        let d = Device(primaryIP: "192.168.0.5", services: [svc], openPorts: [Port(number: 80, serviceName: "http", description: "Web", status: .open, lastSeenOpen: Date())])
        let names = d.displayServices.map { $0.name }
        XCTAssertTrue(names.contains("HTTP"))
        XCTAssertTrue(names.contains("SSH"))
    }

    func testMocksNonEmptyAndUniqueIDs() {
        let mocks = Device.allMocks
        XCTAssertFalse(mocks.isEmpty)
        let ids = Set(mocks.map { $0.id })
        XCTAssertEqual(ids.count, mocks.count)
    }
}
