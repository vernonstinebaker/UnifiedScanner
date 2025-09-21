import XCTest
@testable import UnifiedScanner

final class OUILookupServiceTests: XCTestCase {
    func testVendorLookupParsesCSV() {
        let vendor = OUILookupService.shared.vendorFor(mac: "F4:EA:B5:12:34:56")
        XCTAssertEqual(vendor, "Extreme Networks Headquarters")
    }
}
