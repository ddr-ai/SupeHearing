import XCTest

final class SuperHearingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchAndTabs() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify Tab Bar items exist
        XCTAssertTrue(app.tabBars.buttons["Record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Recordings"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)

        // Switch to Recordings tab
        app.tabBars.buttons["Recordings"].tap()
        XCTAssertTrue(app.navigationBars["Recordings"].waitForExistence(timeout: 3))

        // Switch to Settings tab
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        // Switch back to Record tab
        app.tabBars.buttons["Record"].tap()
        XCTAssertTrue(app.navigationBars["SuperHearing"].waitForExistence(timeout: 3))
    }
}
