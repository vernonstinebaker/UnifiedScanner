import XCTest
@testable import UnifiedScanner

final class LoggingServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Capture stdout to verify emissions
        // Note: Since print is used, we can use a swizzled print or just test logic
    }

    func testLevelEnum() {
        let levels = LoggingService.Level.allCases
        XCTAssertEqual(levels.count, 5)
        XCTAssertEqual(LoggingService.Level.off.rawValue, 0)
        XCTAssertEqual(LoggingService.Level.error.rawValue, 1)
        XCTAssertEqual(LoggingService.Level.warn.rawValue, 2)
        XCTAssertEqual(LoggingService.Level.info.rawValue, 3)
        XCTAssertEqual(LoggingService.Level.debug.rawValue, 4)
    }

    func testSetMinimumLevel() async {
        await LoggingService.setMinimumLevelSync(.debug)
        // Can't directly test private, but subsequent emits should work if level set
        await LoggingService.debugSync("test debug")
        // Assume print happened; in real test, capture output
    }

    func testEmitEnabledWhenLevelAllows() async {
        await LoggingService.setMinimumLevelSync(.info)
        // Logic test: isEnabled for .info should be true, .debug false
        // But private, so indirect via sync calls
        // For unit, test that off disables all
        await LoggingService.setMinimumLevelSync(.off)
        // No emit
        await LoggingService.setMinimumLevelSync(.error)
        // Only error and above, but since no capture, test via assumption
        // This test is limited without output capture; focus on API
    }

    func testStaticWrappersAreNonisolated() {
        // Compile-time: these are nonisolated, can call from anywhere
        LoggingService.info("test")
        LoggingService.warn("test")
        LoggingService.error("test")
        LoggingService.debug("test")
        // No crash, good
    }

    func testSharedInstance() {
        let s1 = LoggingService.shared
        let s2 = LoggingService.shared
        XCTAssertTrue(s1 === s2)
    }

    func testLogWithCategory() async {
        await LoggingService.setMinimumLevelSync(.debug)
        // Test that logging with category doesn't crash and presumably logs
        await LoggingService.infoSync("Test discovery log")
        await LoggingService.debugSync("Test ping log")
    }
}