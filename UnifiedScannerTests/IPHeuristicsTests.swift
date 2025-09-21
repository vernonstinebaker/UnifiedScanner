import XCTest
@testable import UnifiedScanner

final class IPHeuristicsTests: XCTestCase {
    func testBestDisplayIPPrivateIPv4Preference() {
        let ips: Set<String> = ["192.168.1.1", "10.0.0.1", "172.16.0.1", "8.8.8.8"]
        XCTAssertEqual(IPHeuristics.bestDisplayIP(ips), "10.0.0.1") // stableSort is lexical, 10 < 172 < 192
    }

    func testBestDisplayIPPublicIPv4Fallback() {
        let ips: Set<String> = ["8.8.8.8", "1.1.1.1", "203.0.113.1"]
        XCTAssertEqual(IPHeuristics.bestDisplayIP(ips), "1.1.1.1") // lexical sort
    }

    func testBestDisplayIPv6Fallback() {
        let ips: Set<String> = ["fe80::1%lo0", "2001:db8::1", "2607:f8b0:4004:806::200e"]
        XCTAssertEqual(IPHeuristics.bestDisplayIP(ips), "2001:db8::1") // lexical
    }

    func testBestDisplayIPMixed() {
        let ips: Set<String> = ["192.168.1.1", "fe80::1", "8.8.8.8"]
        XCTAssertEqual(IPHeuristics.bestDisplayIP(ips), "192.168.1.1")
    }

    func testBestDisplayIPLinkLocalIPv4() {
        let ips: Set<String> = ["169.254.1.1", "169.254.2.2"]
        XCTAssertEqual(IPHeuristics.bestDisplayIP(ips), "169.254.1.1") // lexical, no private
    }

    func testIPv4Validation() {
        XCTAssertTrue("192.168.1.1".isIPv4)
        XCTAssertTrue("255.255.255.255".isIPv4)
        XCTAssertFalse("192.168.1.256".isIPv4)
        XCTAssertFalse("192.168.1".isIPv4)
        XCTAssertFalse("abc.def.ghi.jkl".isIPv4)
        XCTAssertFalse("2001:db8::1".isIPv4)
    }

    func testPrivateIPv4Validation() {
        XCTAssertTrue("10.0.0.1".isPrivateIPv4)
        XCTAssertTrue("172.16.0.1".isPrivateIPv4)
        XCTAssertTrue("172.31.0.1".isPrivateIPv4)
        XCTAssertTrue("192.168.0.1".isPrivateIPv4)
        XCTAssertFalse("8.8.8.8".isPrivateIPv4)
        XCTAssertFalse("172.32.0.1".isPrivateIPv4) // 172.32 not private
        XCTAssertFalse("169.254.1.1".isPrivateIPv4)
        XCTAssertFalse("invalid".isPrivateIPv4)
    }

    func testStableSort() {
        let sorted = ["b", "a", "c"].sorted(by: IPHeuristics.stableSort)
        XCTAssertEqual(sorted, ["a", "b", "c"])
    }

    func testEmptySet() {
        XCTAssertNil(IPHeuristics.bestDisplayIP([]))
    }

    func testSingleIP() {
        XCTAssertEqual(IPHeuristics.bestDisplayIP(["192.168.1.1"]), "192.168.1.1")
        XCTAssertEqual(IPHeuristics.bestDisplayIP(["fe80::1"]), "fe80::1")
    }

    func testInvalidIPsIgnored() {
        let ips: Set<String> = ["192.168.1", "invalid", "fe80::1"]
        XCTAssertEqual(IPHeuristics.bestDisplayIP(ips), "fe80::1") // Only valid IPv6
    }
}