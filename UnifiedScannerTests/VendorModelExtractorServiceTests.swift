import XCTest
@testable import UnifiedScanner

final class VendorModelExtractorServiceTests: XCTestCase {
    func testExtractsVendorAndModelPrimaryKeys() {
        let fp = ["Manufacturer": "Apple", "ModelName": "MacBookPro16,1"]
        let result = VendorModelExtractorService.extract(from: fp)
        XCTAssertEqual(result.vendor, "Apple")
        XCTAssertEqual(result.model, "MacBookPro16,1")
    }

    func testTYFallbackForModel() {
        let fp = ["TY": "Brother HL-2270DW"]
        let result = VendorModelExtractorService.extract(from: fp)
        XCTAssertNil(result.vendor)
        XCTAssertEqual(result.model, "Brother HL-2270DW")
    }

    func testVendorPriorityOrder() {
        // Provide multiple vendor-like keys; expect first matching key order vendor>manufacturer>brand>...
        let fp = ["Brand": "AltCorp", "Manufacturer": "Globex", "Company": "ExampleCo"]
        let result = VendorModelExtractorService.extract(from: fp)
        // vendor key absent, so should choose manufacturer over brand (since manufacturer appears earlier in vendorKeys list than brand?)
        // vendorKeys order: vendor, manufacturer, brand, manu, mf, company
        XCTAssertEqual(result.vendor, "Globex")
    }

    func testAppleExtendedVendorKeys() {
        let fp = ["ACL": "Apple Inc.", "MD": "MacBookPro16,1"]
        let result = VendorModelExtractorService.extract(from: fp)
        XCTAssertEqual(result.vendor, "Apple")
        XCTAssertEqual(result.model, "MacBookPro16,1")
    }
}
