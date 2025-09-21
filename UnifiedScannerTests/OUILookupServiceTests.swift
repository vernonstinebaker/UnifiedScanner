import XCTest
@testable import UnifiedScanner

final class OUILookupServiceTests: XCTestCase {
    func testVendorLookupParsesCSV() {
        let vendor = OUILookupService.shared.vendorFor(mac: "F4:EA:B5:12:34:56")
        XCTAssertEqual(vendor, "Extreme Networks Headquarters")
    }

    func testVendorLookupCaseInsensitive() {
        let vendor = OUILookupService.shared.vendorFor(mac: "f4:ea:b5:12:34:56")
        XCTAssertEqual(vendor, "Extreme Networks Headquarters")
    }

    func testVendorLookupInvalidMAC() {
        let vendor = OUILookupService.shared.vendorFor(mac: "invalid")
        XCTAssertNil(vendor)
    }

    func testVendorLookupShortMAC() {
        let vendor = OUILookupService.shared.vendorFor(mac: "F4:EA:B5")
        XCTAssertEqual(vendor, "Extreme Networks Headquarters")
    }
}
