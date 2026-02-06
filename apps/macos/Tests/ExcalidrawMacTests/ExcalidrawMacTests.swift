import XCTest
@testable import ExcalidrawMac

final class ExcalidrawMacTests: XCTestCase {
    func testDisplayNameHidesExcalidrawExtension() {
        XCTAssertEqual(
            ExcalidrawFileName.displayName(from: "diagram.excalidraw"),
            "diagram"
        )
    }

    func testDisplayNameKeepsOtherExtensions() {
        XCTAssertEqual(
            ExcalidrawFileName.displayName(from: "diagram.json"),
            "diagram.json"
        )
    }

    func testNormalizedFileNameAppendsExcalidrawExtension() {
        XCTAssertEqual(
            ExcalidrawFileName.normalizedFileName(from: "diagram"),
            "diagram.excalidraw"
        )
    }

    func testNormalizedFileNameKeepsExistingExcalidrawExtension() {
        XCTAssertEqual(
            ExcalidrawFileName.normalizedFileName(from: "diagram.excalidraw"),
            "diagram.excalidraw"
        )
    }

    func testSidebarCollapseThreshold() {
        XCTAssertFalse(SidebarBehavior.shouldCollapse(width: 50))
        XCTAssertTrue(SidebarBehavior.shouldCollapse(width: 49.9))
    }

    func testThemeBootstrapScriptContainsThemeAndBackground() {
        let darkScript = WebCanvasViewModel.makeThemeBootstrapScript(theme: "dark")
        XCTAssertTrue(darkScript.contains("window.__XEXCALIDRAW_THEME = \"dark\""))
        XCTAssertTrue(darkScript.contains("#1e1e1e"))

        let lightScript = WebCanvasViewModel.makeThemeBootstrapScript(theme: "light")
        XCTAssertTrue(lightScript.contains("window.__XEXCALIDRAW_THEME = \"light\""))
        XCTAssertTrue(lightScript.contains("#ffffff"))
    }
}
