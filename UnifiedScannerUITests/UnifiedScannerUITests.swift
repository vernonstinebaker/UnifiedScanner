import XCTest

final class UnifiedScannerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsDevicesTitle() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UNIFIEDSCANNER_DISABLE_NETWORK_DISCOVERY"] = "1"
        app.launch()

        let devicesTitle = app.staticTexts["Devices"]
        let navigationBar = app.navigationBars["Devices"]

        XCTAssertTrue(devicesTitle.waitForExistence(timeout: 5) || navigationBar.exists,
                      "Expected main device list to be visible after launch")
    }
}
