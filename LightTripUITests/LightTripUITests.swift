import XCTest

final class LightTripUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSampleImportAndCoreNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()

        app.buttons["Import Trip"].tap()
        app.buttons["Load Sample Trip"].tap()
        app.buttons["Review"].tap()
        XCTAssertTrue(app.navigationBars["Import Review"].waitForExistence(timeout: 3))
        app.buttons["Create Trip"].tap()

        XCTAssertTrue(app.staticTexts["Western Sichuan Autumn Trip"].waitForExistence(timeout: 3))
        app.staticTexts["Western Sichuan Autumn Trip"].tap()
        XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.navigationBars["Timeline"].exists)
        app.tabBars.buttons["Bookings"].tap()
        XCTAssertTrue(app.navigationBars["Bookings"].exists)
        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(app.navigationBars["Original Plan"].exists)
    }
}
