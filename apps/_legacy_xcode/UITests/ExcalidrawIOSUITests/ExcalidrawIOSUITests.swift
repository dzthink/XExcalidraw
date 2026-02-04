import XCTest

final class ExcalidrawIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCanvasLoads() throws {
        let app = XCUIApplication()
        app.launch()
        let status = app.staticTexts["canvas-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let predicate = NSPredicate(format: "label == %@ OR value == %@", "Canvas ready", "Canvas ready")
        let readyExpectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
        let result = XCTWaiter.wait(for: [readyExpectation], timeout: 20)
        if result != .completed {
            let valueText = status.value as? String ?? ""
            let labelText = status.label
            XCTFail("Canvas not ready. Current status: label=\(labelText) value=\(valueText)")
        }

        let styleStatus = app.staticTexts["canvas-style-status"]
        XCTAssertTrue(styleStatus.waitForExistence(timeout: 5))
        let stylePredicate = NSPredicate(format: "label == %@ OR value == %@", "Styles ready", "Styles ready")
        let styleExpectation = XCTNSPredicateExpectation(predicate: stylePredicate, object: styleStatus)
        let styleResult = XCTWaiter.wait(for: [styleExpectation], timeout: 20)
        if styleResult != .completed {
            let valueText = styleStatus.value as? String ?? ""
            let labelText = styleStatus.label
            XCTFail("Styles not ready. Current status: label=\(labelText) value=\(valueText)")
        }
    }
}
