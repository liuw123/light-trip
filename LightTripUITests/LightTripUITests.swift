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
        let reviewButton = app.buttons["Review"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 5))
        XCTAssertTrue(reviewButton.isEnabled)
        reviewButton.tap()
        XCTAssertTrue(app.buttons["Create Trip"].waitForExistence(timeout: 10))
        app.buttons["Create Trip"].tap()

        XCTAssertTrue(app.staticTexts["Western Sichuan Autumn Trip"].waitForExistence(timeout: 10))
        app.staticTexts["Western Sichuan Autumn Trip"].tap()
        XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["Fly to Chengdu"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Bookings"].tap()
        XCTAssertTrue(app.staticTexts["Example Airline"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(app.staticTexts["Light Trip JSON"].waitForExistence(timeout: 5))
    }
}
