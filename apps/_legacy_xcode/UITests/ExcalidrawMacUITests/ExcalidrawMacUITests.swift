import XCTest

final class ExcalidrawMacUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCanvasLoads() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
        app.launch()
        app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout: 3) { app.typeKey("n", modifierFlags: .command) }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["canvas-ready"].waitForExistence(timeout: 30), app.debugDescription)
    }

    func testSidebarToggleButtonChangesAccessibilityLabel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
        app.launch()
        app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout: 3) { app.typeKey("n", modifierFlags: .command) }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5), app.debugDescription)

        let toggleButton = app.buttons["sidebar-toggle-button"]
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 10))

        let initialLabel = toggleButton.label
        XCTAssertTrue(initialLabel == "Collapse navigation" || initialLabel == "Show navigation")

        toggleButton.tap()

        let toggledLabel = toggleButton.label
        XCTAssertNotEqual(initialLabel, toggledLabel)
        XCTAssertTrue(toggledLabel == "Collapse navigation" || toggledLabel == "Show navigation")
    }
}
