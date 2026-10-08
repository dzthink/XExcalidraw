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

    func testToolbarSwitchesBetweenDrawingAndMindMap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
        app.launch(); app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout: 3) { app.typeKey("n", modifierFlags: .command) }
        let window = app.windows.firstMatch
        let drawing = window.descendants(matching: .any)["file-row-Test Canvas.excalidraw"]
        let mindMap = window.descendants(matching: .any)["file-row-Test Mind Map.mindmap"]
        let outline = window.radioButtons["大纲"]
        let map = window.radioButtons["思维导图"]
        let rectangle = window.buttons["Rectangle"]
        let webDrawingTools = window.radioButtons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rectangle"))
        XCTAssertTrue(drawing.waitForExistence(timeout: 10))
        XCTAssertTrue(window.descendants(matching: .any)["canvas-ready"].waitForExistence(timeout: 30))
        app.activate()
        drawing.click()
        XCTAssertTrue(rectangle.waitForExistence(timeout: 30))

        // Revisit the same drawing without changing its tool state between loads.
        for _ in 0..<3 {
            mindMap.click()
            XCTAssertTrue(outline.waitForExistence(timeout: 10))
            XCTAssertTrue(map.exists)
            XCTAssertFalse(rectangle.exists)
            map.click()
            let mapSelected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 1"), object: map)
            XCTAssertEqual(XCTWaiter.wait(for: [mapSelected], timeout: 10), .completed)
            drawing.click()
            XCTAssertTrue(rectangle.waitForExistence(timeout: 10))
            XCTAssertFalse(outline.exists)
            XCTAssertFalse(map.exists)
            XCTAssertEqual(webDrawingTools.count, 0, "Narrow desktop windows use only the native drawing toolbar")
        }
        rectangle.click()
        let toolSelected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Selected"), object: rectangle)
        XCTAssertEqual(XCTWaiter.wait(for: [toolSelected], timeout: 10), .completed)
        let leftControls = window.descendants(matching: .any)["drawing-left-controls"]
        let rightControls = window.descendants(matching: .any)["drawing-right-controls"]
        XCTAssertTrue(leftControls.exists)
        XCTAssertTrue(rightControls.exists)
        for label in ["Frame", "Embed", "Laser pointer"] {
            let tool = leftControls.buttons[label]
            XCTAssertTrue(tool.exists, "Additional tools remain directly visible in the editor")
            XCTAssertFalse(window.toolbars.buttons[label].exists)
            tool.click()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Selected"), object: tool)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        }
        rectangle.click()
        let format = window.buttons["drawing-format-button"]
        format.click()
        let formatSelected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Selected"), object: format)
        XCTAssertEqual(XCTWaiter.wait(for: [formatSelected], timeout: 10), .completed)
        XCTAssertTrue(window.popUpButtons["Stroke"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(window.buttons["Edit"].firstMatch.exists, "The native format button replaces the web footer entry")
        let library = window.buttons["drawing-library-button"]
        XCTAssertTrue(rightControls.buttons["drawing-library-button"].exists)
        XCTAssertFalse(window.toolbars.buttons["Library"].exists)
        library.click()
        let librarySelected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Selected"), object: library)
        XCTAssertEqual(XCTWaiter.wait(for: [librarySelected], timeout: 10), .completed)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native drawing side controls and format and library panels"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        library.click()
        let libraryClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "Selected"), object: library)
        XCTAssertEqual(XCTWaiter.wait(for: [libraryClosed], timeout: 10), .completed)
        format.click()
        let formatClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "Selected"), object: format)
        XCTAssertEqual(XCTWaiter.wait(for: [formatClosed], timeout: 10), .completed)
        XCTAssertFalse(window.popUpButtons["Stroke"].firstMatch.exists)
        // Excalidraw changes its panel layout as the editor grows beyond mobile width.
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -3, dy: -3))
        corner.click(forDuration: 0.1, thenDragTo: corner.withOffset(CGVector(dx: 220, dy: 0)))
        let widerWindow = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in window.frame.width > 1000 }, object: window)
        XCTAssertEqual(XCTWaiter.wait(for: [widerWindow], timeout: 10), .completed)
        format.click()
        XCTAssertTrue(window.popUpButtons["Stroke"].firstMatch.waitForExistence(timeout: 5))
        library.click()
        let wideLibrarySelected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Selected"), object: library)
        XCTAssertEqual(XCTWaiter.wait(for: [wideLibrarySelected], timeout: 10), .completed)
        let wideScreenshot = XCTAttachment(screenshot: app.screenshot())
        wideScreenshot.name = "Native drawing controls and panels in a wide window"
        wideScreenshot.lifetime = .keepAlways
        add(wideScreenshot)
        mindMap.click()
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertFalse(rectangle.exists)
        XCTAssertFalse(leftControls.exists)
        XCTAssertFalse(rightControls.exists)
        outline.click()
        let outlineSelected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 1"), object: outline)
        XCTAssertEqual(XCTWaiter.wait(for: [outlineSelected], timeout: 10), .completed)
    }

    func testNodeDragReparentsSubtreeAndPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
        app.launchEnvironment["SIYE_UI_TEST_NODE_DRAG"] = "1"
        app.launch(); app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout: 3) { app.typeKey("n", modifierFlags: .command) }
        let window = app.windows.firstMatch
        let row = window.descendants(matching: .any)["file-row-Test Mind Map.mindmap"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.click()
        let moving = window.staticTexts["移动节点"].firstMatch
        let target = window.staticTexts["目标父节点"].firstMatch
        XCTAssertTrue(moving.waitForExistence(timeout: 30)); XCTAssertTrue(target.exists)
        moving.rightClick()
        let focus = window.menuItems["进入此节点"]
        XCTAssertTrue(focus.waitForExistence(timeout: 5)); focus.click()
        XCTAssertFalse(target.exists)
        window.buttons["节点操作"].click()
        let exitFocus = window.buttons["返回完整导图"]
        XCTAssertTrue(exitFocus.waitForExistence(timeout: 5))
        XCTAssertFalse(window.buttons["进入此节点"].exists)
        XCTAssertFalse(window.buttons["返回上级"].exists)
        XCTAssertEqual(window.buttons.matching(identifier: "返回完整导图").count, 1)
        let focusedScreenshot = XCTAttachment(screenshot: app.screenshot())
        focusedScreenshot.name = "Desktop context focus synchronized toolbar"; focusedScreenshot.lifetime = .keepAlways; add(focusedScreenshot)
        exitFocus.click()
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        moving.click()
        window.buttons["节点操作"].click()
        XCTAssertTrue(window.buttons["进入此节点"].waitForExistence(timeout: 5))
        window.buttons["关闭菜单"].click()
        moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.1, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: 12)))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Desktop dragged node with descendants"; screenshot.lifetime = .keepAlways; add(screenshot)
        window.radioButtons["大纲"].click()
        let fold = window.buttons.matching(identifier: "折叠节点").firstMatch
        XCTAssertTrue(fold.waitForExistence(timeout: 10)); fold.click()
        XCTAssertEqual(window.buttons.matching(identifier: "选择节点").count, 1, "Folding target hides the moving subtree")
        window.buttons["展开节点"].firstMatch.click()
        XCTAssertEqual(window.buttons.matching(identifier: "选择节点").count, 3)
        // Reopen the document to verify that the committed parent is persisted.
        window.descendants(matching: .any)["file-row-Test Canvas.excalidraw"].click()
        let canvasShown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: window.radioButtons["大纲"])
        XCTAssertEqual(XCTWaiter.wait(for: [canvasShown], timeout: 10), .completed)
        row.click()
        XCTAssertTrue(window.buttons.matching(identifier: "折叠节点").firstMatch.waitForExistence(timeout: 10))
        window.buttons.matching(identifier: "折叠节点").firstMatch.click()
        XCTAssertEqual(window.buttons.matching(identifier: "选择节点").count, 1, "Saved tree retains parent relationship")
    }

    func testFileContextMenuOpensDocumentInNewWindow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
        app.launch()
        app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout: 3) { app.typeKey("n", modifierFlags: .command) }
        let originalWindow = app.windows.firstMatch
        XCTAssertTrue(originalWindow.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(originalWindow.descendants(matching: .any)["canvas-ready"].waitForExistence(timeout: 30))
        let initialWindowCount = app.windows.count
        let fileRow = originalWindow.descendants(matching: .any)["file-row-Test Canvas.excalidraw"]
        XCTAssertTrue(fileRow.waitForExistence(timeout: 10))
        fileRow.rightClick()
        let menuItem = app.menuItems["在新窗口打开"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5))
        menuItem.click()

        let extraWindow = app.windows.element(boundBy: initialWindowCount)
        XCTAssertTrue(extraWindow.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.windows.count, initialWindowCount + 1)
        let newWindow = app.windows["Test Canvas"]
        XCTAssertTrue(newWindow.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(newWindow.descendants(matching: .any)["canvas-ready"].waitForExistence(timeout: 30))
        XCTAssertFalse(newWindow.descendants(matching: .any)["documents-sidebar"].exists)
        XCTAssertFalse(newWindow.buttons["sidebar-toggle-button"].exists)
        XCTAssertFalse(newWindow.buttons["import-document-button"].exists)
        XCTAssertTrue(originalWindow.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Document opened in a new window"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertEqual(app.windows.count, initialWindowCount)
    }

    func testMindMapEditsSynchronizeBetweenWindows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
        app.launch()
        app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout: 3) { app.typeKey("n", modifierFlags: .command) }
        let original = app.windows.containing(.any, identifier: "documents-sidebar").firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 10))
        let row = original.descendants(matching: .any)["file-row-Test Mind Map.mindmap"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        let originalTitle = original.descendants(matching: .any).matching(identifier: "文档标题").firstMatch
        XCTAssertTrue(originalTitle.waitForExistence(timeout: 10))
        row.rightClick()
        let menuItem = app.menuItems["在新窗口打开"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5))
        menuItem.click()
        let editor = app.windows["Test Mind Map"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let editorTitle = editor.descendants(matching: .any).matching(identifier: "文档标题").firstMatch
        XCTAssertTrue(editorTitle.waitForExistence(timeout: 10))
        editorTitle.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Updated in new window")
        let syncedFromEditor = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "Updated in new window"), object: originalTitle)
        XCTAssertEqual(XCTWaiter.wait(for: [syncedFromEditor], timeout: 15), .completed, app.debugDescription)
        originalTitle.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Updated in original window")
        let syncedFromOriginal = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "Updated in original window"), object: editorTitle)
        XCTAssertEqual(XCTWaiter.wait(for: [syncedFromOriginal], timeout: 15), .completed, app.debugDescription)
        original.descendants(matching: .any)["canvas-ready"].scroll(byDeltaX: 0, deltaY: 180)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Synchronized windows after scrolling at the top"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        editor.click()
        app.typeKey("w", modifierFlags: .command)
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
