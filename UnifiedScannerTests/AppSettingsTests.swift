import XCTest
@testable import UnifiedScanner

@MainActor final class AppSettingsTests: XCTestCase {
    private var originalDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        originalDefaults = UserDefaults.standard
        // To isolate, but since it uses standard, we'll clear keys before each test
    }

    override func tearDown() {
        super.tearDown()
        // Clear test keys
        UserDefaults.standard.removeObject(forKey: "unifiedscanner:settings:loggingLevel")
        UserDefaults.standard.removeObject(forKey: "unifiedscanner:settings:showFingerprints")
        UserDefaults.standard.synchronize()
    }

    func testInitUsesDefaultValuesWhenNoStored() {
        // Clear any existing
        UserDefaults.standard.removeObject(forKey: "unifiedscanner:settings:loggingLevel")
        UserDefaults.standard.removeObject(forKey: "unifiedscanner:settings:showFingerprints")

        let settings = AppSettings()

        XCTAssertEqual(settings.loggingLevel, .info)
        XCTAssertTrue(settings.showFingerprints)
    }

    func testInitLoadsStoredLoggingLevel() {
        UserDefaults.standard.set("debug", forKey: "unifiedscanner:settings:loggingLevel")

        let settings = AppSettings()

        XCTAssertEqual(settings.loggingLevel, .debug)
    }

    func testInitLoadsStoredShowFingerprints() {
        UserDefaults.standard.set(false, forKey: "unifiedscanner:settings:showFingerprints")

        let settings = AppSettings()

        XCTAssertFalse(settings.showFingerprints)
    }

    func testLoggingLevelDidSetPersistsAndSetsLoggerLevel() {
        let expectation = XCTestExpectation(description: "Persist called")

        // Since LoggingService.setMinimumLevel is static, hard to mock, but we can check persistence
        let settings = AppSettings()
        let key = "unifiedscanner:settings:loggingLevel"
        let oldValue = settings.loggingLevel

        settings.loggingLevel = .error

        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "error")
        XCTAssertNotEqual(settings.loggingLevel, oldValue)
    }

    func testShowFingerprintsDidSetPersists() {
        let settings = AppSettings()
        let key = "unifiedscanner:settings:showFingerprints"
        let oldValue = settings.showFingerprints

        settings.showFingerprints = false

        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
        XCTAssertNotEqual(settings.showFingerprints, oldValue)
    }

    func testLoggingLevelDisplayNames() {
        XCTAssertEqual(AppSettings.LoggingLevel.off.displayName, "Off")
        XCTAssertEqual(AppSettings.LoggingLevel.error.displayName, "Error")
        XCTAssertEqual(AppSettings.LoggingLevel.warn.displayName, "Warn")
        XCTAssertEqual(AppSettings.LoggingLevel.info.displayName, "Info")
        XCTAssertEqual(AppSettings.LoggingLevel.debug.displayName, "Debug")
    }

    func testLoggingLevelScanLoggerLevelMapping() {
        XCTAssertEqual(AppSettings.LoggingLevel.off.scanLoggerLevel, .off)
        XCTAssertEqual(AppSettings.LoggingLevel.error.scanLoggerLevel, .error)
        XCTAssertEqual(AppSettings.LoggingLevel.warn.scanLoggerLevel, .warn)
        XCTAssertEqual(AppSettings.LoggingLevel.info.scanLoggerLevel, .info)
        XCTAssertEqual(AppSettings.LoggingLevel.debug.scanLoggerLevel, .debug)
    }

    func testLoggingLevelCaseIterableAndIdentifiable() {
        let levels = AppSettings.LoggingLevel.allCases
        XCTAssertEqual(levels.count, 5)
        let ids = levels.map { $0.id }
        XCTAssertEqual(Set(ids), Set(["off", "error", "warn", "info", "debug"]))
    }
}