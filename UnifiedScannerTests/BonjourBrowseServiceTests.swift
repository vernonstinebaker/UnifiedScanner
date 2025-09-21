import XCTest
@testable import UnifiedScanner

final class BonjourBrowseServiceTests: XCTestCase {
    func testValidServiceTypeRegex() {
        let valid = [
            "_http._tcp.",
            "_ssh._udp.",
            "_airplay._tcp.",
            "_device-info._tcp."
        ]
        for type in valid {
            let isValid = BonjourBrowseService.isValidServiceType(type)
            XCTAssertTrue(isValid, "Should be valid: \(type)")
        }

        let invalid = [
            "http._tcp.",
            "_http.tcp.",
            "_http._tcpp.",
            "_a_b_c._tcp.",
            "plain"
        ]
        for type in invalid {
            let isValid = BonjourBrowseService.isValidServiceType(type)
            XCTAssertFalse(isValid, "Should be invalid: \(type)")
        }
    }

    func testPermittedTypesIOS() {
        #if os(iOS)
        let permitted = BonjourBrowseService.permittedTypesIOS
        XCTAssertTrue(permitted.contains("_airplay._tcp."))
        XCTAssertTrue(permitted.contains("_ssh._tcp."))
        XCTAssertFalse(permitted.contains("_invalid._tcp."))
        XCTAssertEqual(permitted.count, 18) // From code
        #else
        // Skip on macOS
        #endif
    }

    func testInitSetsProperties() {
        let service = BonjourBrowseService(curatedServiceTypes: ["_http._tcp."], dynamicBrowserCap: 10)
        XCTAssertEqual(service.curatedServiceTypes, ["_http._tcp."])
        XCTAssertEqual(service.dynamicBrowserCap, 10)
    }

    // Note: Full start and delegate tests require mocking NetServiceBrowser, which is not straightforward in unit tests
    // Integration tests in BonjourDiscoveryProviderTests cover behavior
}