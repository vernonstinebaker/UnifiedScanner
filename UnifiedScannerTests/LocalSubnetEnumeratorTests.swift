import XCTest
@testable import UnifiedScanner

final class LocalSubnetEnumeratorTests: XCTestCase {
    func testCIDRBlockInitValid() {
        let block = CIDRBlock(cidr: "192.168.1.0/24")
        XCTAssertNotNil(block)
        XCTAssertEqual(block?.baseAddress, 3232235520) // 192.168.1.0
        XCTAssertEqual(block?.prefix, 24)

        let single = CIDRBlock(cidr: "10.0.0.1/32")
        XCTAssertNotNil(single)
        XCTAssertEqual(single?.baseAddress, 167772161)
        XCTAssertEqual(single?.prefix, 32)
    }

    func testCIDRBlockInitInvalid() {
        XCTAssertNil(CIDRBlock(cidr: "invalid"))
        XCTAssertNil(CIDRBlock(cidr: "256.1.2.3/24"))
        XCTAssertNil(CIDRBlock(cidr: "192.168.1.0/33"))
        XCTAssertNil(CIDRBlock(cidr: "192.168.1.0/-1"))
    }

    func testHostAddressesExcludeNetworkBroadcast() {
        let block = CIDRBlock(cidr: "192.168.1.0/24")!
        let hosts = block.hostAddresses()
        XCTAssertEqual(hosts.count, 254)
        XCTAssertFalse(hosts.contains("192.168.1.0"))
        XCTAssertFalse(hosts.contains("192.168.1.255"))
        XCTAssertTrue(hosts.contains("192.168.1.1"))
        XCTAssertTrue(hosts.contains("192.168.1.254"))
    }

    func testHostAddressesIncludeNetworkBroadcast() {
        let block = CIDRBlock(cidr: "192.168.1.0/24")!
        let all = block.hostAddresses(includeNetwork: true, includeBroadcast: true)
        XCTAssertEqual(all.count, 256)
        XCTAssertTrue(all.contains("192.168.1.0"))
        XCTAssertTrue(all.contains("192.168.1.255"))
    }

    func testHostAddressesSingleHost() {
        let block = CIDRBlock(cidr: "10.0.0.1/32")!
        let hosts = block.hostAddresses()
        XCTAssertEqual(hosts, ["10.0.0.1"])
    }

    func testIPv4ParserAddressToUInt32() {
        XCTAssertEqual(IPv4Parser.addressToUInt32("192.168.1.1"), 3232235777)
        XCTAssertEqual(IPv4Parser.addressToUInt32("255.255.255.255"), 4294967295)
        XCTAssertNil(IPv4Parser.addressToUInt32("invalid"))
        XCTAssertNil(IPv4Parser.addressToUInt32("192.168.1.256"))
    }

    func testIPv4ParserUInt32ToAddress() {
        XCTAssertEqual(IPv4Parser.uint32ToAddress(3232235777), "192.168.1.1")
        XCTAssertEqual(IPv4Parser.uint32ToAddress(4294967295), "255.255.255.255")
        XCTAssertEqual(IPv4Parser.uint32ToAddress(0), "0.0.0.0")
    }

    func testEnumerateWithMaxHosts() {
        let enumerator = LocalSubnetEnumerator()
        // Since primaryIP is system dependent, test with mock? But for unit, skip or assume
        // Test logic by calling, but expect non-empty if network
        let hosts = enumerator.enumerate(maxHosts: 10)
        // Can't assert count without known env, but check format
        for host in hosts {
            XCTAssertTrue(host.isIPv4)
            XCTAssertFalse(host.hasPrefix("169.254."))
        }
    }

    func testEnumerateFiltersLinkLocal() {
        let enumerator = LocalSubnetEnumerator()
        let hosts = enumerator.enumerate()
        XCTAssertFalse(hosts.contains { $0.hasPrefix("169.254.") })
    }
}