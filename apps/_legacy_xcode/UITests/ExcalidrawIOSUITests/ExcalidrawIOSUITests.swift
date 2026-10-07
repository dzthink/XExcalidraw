import XCTest
import UIKit

final class ExcalidrawIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingOpensFolderPicker() {
        let app = makeApplication()
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "onboarding"
        app.launch()
        let chooseFolder = app.buttons["选择文件夹"]
        XCTAssertTrue(chooseFolder.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["让想法自由生长"].exists)
        chooseFolder.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        attachScreenshot(app, name: "Folder picker")
    }

    func testEditorLeftEdgeSwipeReturnsAndSaves() {
        let app = makeApplication()
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
        app.launch()
        let all = app.buttons["all-documents"]
        XCTAssertTrue(all.waitForExistence(timeout: 15))
        all.tap()
        let file = app.staticTexts["Test Mind Map"].firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15))
        file.tap()
        let web = app.webViews["editor-ready"]
        XCTAssertTrue(web.waitForExistence(timeout: 30))
        web.buttons["大纲"].tap()
        web.staticTexts["中心主题"].firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        app.typeText("edge-swipe-saved")
        swipeEditorLeftEdge(app)
        XCTAssertTrue(file.waitForExistence(timeout: 15))
        XCTAssertFalse(web.exists)

        file.tap()
        let saved = web.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "edge-swipe-saved")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 30))
        web.buttons["思维导图"].tap()
        swipeEditorLeftEdge(app)
        XCTAssertTrue(file.waitForExistence(timeout: 15))

        let canvas = app.staticTexts["Test Canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        canvas.tap()
        XCTAssertTrue(web.waitForExistence(timeout: 30))
        swipeEditorLeftEdge(app)
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        XCTAssertFalse(web.exists)
        attachScreenshot(app, name: "Returned from editor with left edge swipe")
    }

    private func swipeEditorLeftEdge(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.4))
            .withOffset(CGVector(dx: 2, dy: 0))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    func testMobileNodeSelectionAndLongPressReparent() {
        let app = makeApplication()
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
        app.launchEnvironment["SIYE_UI_TEST_NODE_DRAG"] = "1"
        app.launch()
        let all = app.buttons["all-documents"]
        XCTAssertTrue(all.waitForExistence(timeout: 15)); all.tap()
        let file = app.staticTexts["Test Mind Map"].firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15)); file.tap()
        let web = app.webViews["editor-ready"]
        XCTAssertTrue(web.waitForExistence(timeout: 30))
        let moving = web.staticTexts["移动节点"].firstMatch
        let target = web.staticTexts["目标父节点"].firstMatch
        XCTAssertTrue(moving.waitForExistence(timeout: 10)); XCTAssertTrue(target.exists)
        moving.tap()
        XCTAssertTrue(web.buttons["编辑节点"].waitForExistence(timeout: 5))
        XCTAssertTrue(web.buttons["添加子节点"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        attachScreenshot(app, name: "iPhone single tap node action bar")
        web.buttons["更多节点操作"].tap()
        XCTAssertFalse(web.buttons["增加缩进"].exists)
        XCTAssertFalse(web.buttons["减少缩进"].exists)
        for label in ["进入此节点", "删除节点"] {
            XCTAssertTrue(web.buttons[label].exists)
        }
        web.buttons["进入此节点"].tap()
        XCTAssertFalse(target.exists)
        XCTAssertFalse(web.buttons["返回上级"].exists)
        web.buttons["更多节点操作"].tap()
        let exitFocus = web.buttons["返回完整导图"]
        XCTAssertTrue(exitFocus.waitForExistence(timeout: 5))
        XCTAssertFalse(web.buttons["进入此节点"].exists)
        XCTAssertEqual(web.buttons.matching(identifier: "返回完整导图").count, 1)
        for outside in [web.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.35)), moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))] {
            outside.tap()
            XCTAssertTrue(web.buttons["编辑节点"].exists)
            XCTAssertTrue(web.buttons["添加子节点"].exists)
            XCTAssertTrue(web.buttons["取消选中"].exists)
            XCTAssertFalse(exitFocus.exists, "Outside tap closes only More")
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            web.buttons["更多节点操作"].tap()
            XCTAssertTrue(exitFocus.waitForExistence(timeout: 5))
        }
        attachScreenshot(app, name: "iPhone focus state in node actions")
        exitFocus.tap()
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        moving.tap()
        web.buttons["更多节点操作"].tap()
        XCTAssertTrue(web.buttons["进入此节点"].exists)
        web.buttons["进入此节点"].tap()
        web.buttons["取消选中"].tap()
        XCTAssertTrue(exitFocus.waitForExistence(timeout: 5))
        XCTAssertTrue(exitFocus.isHittable)
        attachScreenshot(app, name: "iPhone toolbar exit without selection")
        exitFocus.tap()
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertFalse(exitFocus.exists)
        moving.tap()
        web.buttons["编辑节点"].tap()
        let accessory = app.otherElements["mindmap-keyboard-accessory"].firstMatch
        XCTAssertTrue(accessory.waitForExistence(timeout: 10))
        accessory.buttons["收起键盘"].tap()
        XCTAssertTrue(web.buttons["编辑节点"].waitForExistence(timeout: 5))
        let start = moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Move beyond the downward alignment band to attach to the target.
        let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: 35))
        start.press(forDuration: 0.6, thenDragTo: end)
        XCTAssertTrue(web.buttons["编辑节点"].waitForExistence(timeout: 5))
        XCTAssertFalse(web.menuItems["添加子节点"].exists)
        attachScreenshot(app, name: "iPhone long press moved subtree")
        web.buttons["大纲"].tap()
        XCTAssertTrue(web.buttons.matching(identifier: "折叠节点").firstMatch.waitForExistence(timeout: 5))
        web.buttons.matching(identifier: "折叠节点").firstMatch.tap()
        XCTAssertEqual(web.buttons.matching(identifier: "选择节点").count, 1, "Folding the new parent hides the entire moving subtree")
        web.buttons["展开节点"].firstMatch.tap()
        XCTAssertEqual(web.buttons.matching(identifier: "选择节点").count, 3)
        app.buttons["返回"].tap()
        XCTAssertTrue(file.waitForExistence(timeout: 15)); file.tap()
        XCTAssertTrue(web.waitForExistence(timeout: 30))
        web.buttons.matching(identifier: "折叠节点").firstMatch.tap()
        XCTAssertEqual(web.buttons.matching(identifier: "选择节点").count, 1, "Reparenting survives close/reopen")
        attachScreenshot(app, name: "iPhone persisted parent relationship")
    }

    func testLayoutDragSiblingOrderAndParentPersistence() {
        for layout in ["right", "left", "down", "side"] {
            let app = makeApplication()
            app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
            app.launchEnvironment["SIYE_UI_TEST_LAYOUT_DRAG"] = layout
            app.launch()
            let all = app.buttons["all-documents"]
            XCTAssertTrue(all.waitForExistence(timeout: 15)); all.tap()
            let file = app.staticTexts["Test Mind Map"].firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 15)); file.tap()
            let web = app.webViews["editor-ready"]
            XCTAssertTrue(web.waitForExistence(timeout: 30))
            let b1 = web.staticTexts["B1"].firstMatch
            let b2 = web.staticTexts["B2"].firstMatch
            let b3 = web.staticTexts["B3"].firstMatch
            let c = web.staticTexts["C"].firstMatch
            XCTAssertTrue(b1.waitForExistence(timeout: 10)); XCTAssertTrue(b2.exists); XCTAssertTrue(b3.exists)
            let down = layout == "down"
            let first = b1.frame, second = b2.frame
            let destination = web.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: (down ? (first.midX + second.midX) / 2 : first.midX) - web.frame.minX,
                dy: (down ? first.midY : (first.midY + second.midY) / 2) - web.frame.minY))
            b3.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.6, thenDragTo: destination)
            XCTAssertTrue(web.buttons["编辑节点"].waitForExistence(timeout: 5))
            let ordered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                down ? b1.frame.midX < b3.frame.midX && b3.frame.midX < b2.frame.midX
                     : b1.frame.midY < b3.frame.midY && b3.frame.midY < b2.frame.midY
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ordered], timeout: 5), .completed, "\(layout): B1, B3, B2")
            XCTAssertTrue(web.staticTexts["保留子节点"].exists)
            attachScreenshot(app, name: "\(layout) iPhone B1 B3 B2 order")
            app.buttons["返回"].tap()
            XCTAssertTrue(file.waitForExistence(timeout: 15)); file.tap()
            XCTAssertTrue(web.waitForExistence(timeout: 30))
            XCTAssertTrue(b3.waitForExistence(timeout: 10))
            if down { XCTAssertLessThan(b1.frame.midX, b3.frame.midX); XCTAssertLessThan(b3.frame.midX, b2.frame.midX) }
            else { XCTAssertLessThan(b1.frame.midY, b3.frame.midY); XCTAssertLessThan(b3.frame.midY, b2.frame.midY) }
            if layout == "side" { XCTAssertLessThan(web.staticTexts["左侧"].firstMatch.frame.midX, web.staticTexts["A"].firstMatch.frame.midX) }
            attachScreenshot(app, name: "\(layout) iPhone persisted sibling order")

            // Move outward into the B1/C lane, without dragging close to B1.
            XCTAssertTrue(c.exists)
            let parent = b1.frame, child = c.frame
            let gap = web.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: (down ? parent.midX : (parent.midX + child.midX) / 2) - web.frame.minX,
                dy: (down ? (parent.midY + child.midY) / 2 : parent.midY) - web.frame.minY))
            b3.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.6, thenDragTo: gap)
            XCTAssertTrue(web.buttons["编辑节点"].waitForExistence(timeout: 5))
            attachScreenshot(app, name: "\(layout) iPhone layout-based reparent")
            web.buttons["大纲"].tap()
            let fold = web.buttons.matching(identifier: "折叠节点").firstMatch
            XCTAssertTrue(fold.waitForExistence(timeout: 5)); fold.tap()
            XCTAssertFalse(b3.exists, "\(layout): B3 is inside B1")
            XCTAssertFalse(web.staticTexts["保留子节点"].exists)
            XCTAssertEqual(web.buttons.matching(identifier: "选择节点").count, layout == "side" ? 3 : 2, "Only B1, B2 and the optional opposite branch remain")
            web.buttons["展开节点"].firstMatch.tap()
            app.buttons["返回"].tap()
            XCTAssertTrue(file.waitForExistence(timeout: 15)); file.tap()
            XCTAssertTrue(web.waitForExistence(timeout: 30))
            XCTAssertTrue(fold.waitForExistence(timeout: 5)); fold.tap()
            XCTAssertFalse(b3.exists, "\(layout): parent change persists")
            XCTAssertEqual(web.buttons.matching(identifier: "选择节点").count, layout == "side" ? 3 : 2, "Reopening preserves the entire moved subtree under B1")
            attachScreenshot(app, name: "\(layout) iPhone persisted parent and subtree")
            app.terminate()
        }
    }

    func testMindMapQuickDoubleReturnCreatesSibling() {
        for mode in ["大纲", "思维导图"] {
            let app = makeApplication()
            app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
            app.launch()
            let all = app.buttons["all-documents"]
            XCTAssertTrue(all.waitForExistence(timeout: 15))
            all.tap()
            let file = app.staticTexts["Test Mind Map"].firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 15))
            file.tap()
            let web = app.webViews["editor-ready"]
            XCTAssertTrue(web.waitForExistence(timeout: 30))
            web.buttons[mode].tap()
            let title = web.staticTexts["中心主题"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            if mode == "思维导图" { title.doubleTap() } else { title.tap() }
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
            app.typeText("single-line\ncontinued\n\nchild-one\n\nchild-two")
            XCTAssertTrue(app.keyboards.firstMatch.exists, "New sibling retains keyboard input")
            app.otherElements["mindmap-keyboard-accessory"].firstMatch.buttons["收起键盘"].tap()
            web.buttons["大纲"].tap()
            attachScreenshot(app, name: "\(mode) double Return input before save")
            XCTAssertEqual(web.buttons.matching(identifier: "选择节点").count, 2, "Root Return creates a child; child Return creates its sibling")
            let firstChild = web.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@", "child-one", "child-one")).firstMatch
            let secondChild = web.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@", "child-two", "child-two")).firstMatch
            XCTAssertTrue(firstChild.exists, app.debugDescription)
            XCTAssertTrue(secondChild.exists)
            let titleContent = web.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value CONTAINS %@", "文档标题", "continued")).firstMatch
            XCTAssertTrue(titleContent.exists, "Single Return retains text in the original node")
            app.buttons["返回"].tap()
            XCTAssertTrue(file.waitForExistence(timeout: 15))
            file.tap()
            XCTAssertTrue(firstChild.waitForExistence(timeout: 30))
            XCTAssertTrue(secondChild.exists)
            XCTAssertEqual(web.buttons.matching(identifier: "选择节点").count, 2)
            attachScreenshot(app, name: "\(mode) double Return creates saved siblings")
            app.terminate()
        }
    }

    func testCanvasAndMindMapOpen() {
        let app = makeApplication()
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
        app.launch()
        for name in ["Test Canvas", "Test Mind Map"] {
            let file = app.staticTexts[name].firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 15), app.debugDescription)
            file.tap()
            XCTAssertTrue(app.webViews["editor-ready"].waitForExistence(timeout: 30), app.debugDescription)
            if name == "Test Mind Map" {
                XCTAssertTrue(app.webViews.staticTexts["中心主题"].firstMatch.waitForExistence(timeout: 10))
            }
            attachScreenshot(app, name: name)
            app.buttons["返回"].tap()
            XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 10))
        }
        app.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "Settings")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["Test Canvas"].firstMatch.waitForExistence(timeout: 10))
    }

    func testCanvasAndMindMapFollowAppearanceChanges() {
        let app = makeApplication()
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
        app.launch()
        for (appearance, isLight) in [("深色", false), ("浅色", true), ("深色", false)] {
            XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 15))
            app.buttons["设置"].tap()
            let option = app.segmentedControls.buttons[appearance]
            XCTAssertTrue(option.waitForExistence(timeout: 10))
            option.tap()
            app.buttons["完成"].tap()
            assertEditorBackgrounds(app, isLight: isLight)
        }
    }

    func testCanvasAndMindMapStartWithLightAppearance() {
        let app = makeApplication()
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
        app.launchArguments = ["-siye.appearance", "light"]
        app.launch()
        assertEditorBackgrounds(app, isLight: true)
    }

    private func assertEditorBackgrounds(_ app: XCUIApplication, isLight: Bool) {
        for name in ["Test Canvas", "Test Mind Map"] {
            let file = app.staticTexts[name].firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 15))
            file.tap()
            let editor = app.webViews["editor-ready"]
            XCTAssertTrue(editor.waitForExistence(timeout: 30))
            if name == "Test Mind Map" {
                XCTAssertTrue(editor.staticTexts["中心主题"].firstMatch.waitForExistence(timeout: 10))
                for mode in ["大纲", "思维导图"] {
                    editor.buttons[mode].tap()
                    assertEditorBackground(app, editor: editor, name: "\(name) \(mode)", isLight: isLight)
                }
            } else {
                assertEditorBackground(app, editor: editor, name: name, isLight: isLight)
            }
            app.buttons["返回"].tap()
        }
    }

    private func assertEditorBackground(_ app: XCUIApplication, editor: XCUIElement, name: String, isLight: Bool) {
        let backgroundMatches = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let brightness = self.backgroundBrightness(editor.screenshot()) else { return false }
            return isLight ? brightness > 0.7 : brightness < 0.35
        }, object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [backgroundMatches], timeout: 10), .completed,
                       "\(name) must follow the \(isLight ? "light" : "dark") appearance")
        attachScreenshot(app, name: "\(name) \(isLight ? "light" : "dark")")
    }

    private func backgroundBrightness(_ screenshot: XCUIScreenshot) -> Double? {
        guard let image = UIImage(data: screenshot.pngRepresentation)?.cgImage,
              let sample = image.cropping(to: CGRect(x: Double(image.width) * 0.85,
                                                     y: Double(image.height) * 0.75,
                                                     width: 5, height: 5)) else { return nil }
        // Sample empty editor space, away from native navigation and editor controls.
        var pixel = [UInt8](repeating: 0, count: 4)
        let rendered = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard rendered else { return nil }
        return (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3 * 255)
    }

    func testMindMapListStylesAboveKeyboard() {
        for mode in ["大纲", "思维导图"] {
            let app = makeApplication()
            app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
            app.launch()
            let file = app.staticTexts["Test Mind Map"].firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 15))
            file.tap()
            XCTAssertTrue(app.webViews["editor-ready"].waitForExistence(timeout: 30))
            app.webViews.buttons[mode].tap()
            let title = app.webViews.staticTexts["中心主题"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            if mode == "思维导图" { title.doubleTap() } else { title.tap() }
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
            let accessory = app.otherElements["mindmap-keyboard-accessory"].firstMatch
            XCTAssertTrue(accessory.waitForExistence(timeout: 10))
            for listStyle in ["无序列表", "有序列表", "待办列表", "无序列表"] {
                let list = accessory.buttons["列表"]
                revealAccessoryButton(list, in: accessory)
                list.tap()
                let option = webToolbarControl(app, label: listStyle)
                XCTAssertTrue(option.waitForExistence(timeout: 5))
                XCTAssertTrue(option.isHittable)
                XCTAssertLessThanOrEqual(option.frame.maxY, accessory.frame.minY)
                option.tap()
                XCTAssertTrue(keyboard.exists, "List conversion must retain text input")
                XCTAssertTrue(accessory.exists)
            }
            let format = accessory.buttons["文字样式"]
            revealAccessoryButton(format, in: accessory)
            format.tap()
            XCTAssertTrue(webToolbarControl(app, label: "增加缩进").isHittable)
            let outdent = webToolbarControl(app, label: "减少缩进")
            XCTAssertTrue(outdent.isHittable)
            outdent.tap()
            XCTAssertTrue(keyboard.exists)
            attachScreenshot(app, name: "\(mode) list conversion")
            app.terminate()
        }
    }

    func testMindMapTaskListsSaveCompletionAndEmptyItems() {
        for mode in ["大纲", "思维导图"] {
            let app = makeApplication()
            app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
            app.launch()
            let file = app.staticTexts["Test Mind Map"].firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 15))
            file.tap()
            let web = app.webViews["editor-ready"]
            XCTAssertTrue(web.waitForExistence(timeout: 30))
            web.buttons[mode].tap()
            let title = web.staticTexts["中心主题"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            if mode == "思维导图" { title.doubleTap() } else { title.tap() }
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
            let accessory = app.otherElements["mindmap-keyboard-accessory"].firstMatch
            XCTAssertTrue(accessory.waitForExistence(timeout: 10))
            // Start in a new empty child so Return can be checked before typing.
            app.typeText("\n\n")
            XCTAssertTrue(keyboard.exists)
            let list = accessory.buttons["列表"]
            revealAccessoryButton(list, in: accessory)
            list.tap()
            let task = webToolbarControl(app, label: "待办列表")
            XCTAssertTrue(task.waitForExistence(timeout: 5))
            XCTAssertFalse(webToolbarControl(app, label: "短横线列表").exists)
            XCTAssertFalse(webToolbarControl(app, label: "增加缩进").exists)
            XCTAssertFalse(webToolbarControl(app, label: "减少缩进").exists)
            task.tap()
            let checks = web.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "完成待办"))
            XCTAssertEqual(checks.count, 1)
            let before = String(describing: checks.element(boundBy: 0).value)
            checks.element(boundBy: 0).tap()
            let completed = String(describing: checks.element(boundBy: 0).value)
            XCTAssertNotEqual(completed, before, app.debugDescription)
            XCTAssertTrue(keyboard.exists, "Checking a task retains keyboard input")
            app.typeText("task-one\n")
            XCTAssertEqual(checks.count, 2, "Return shows a checkbox before any text is entered")
            XCTAssertEqual(String(describing: checks.element(boundBy: 1).value), before, "New task is unfinished")
            XCTAssertFalse(web.buttons["在块后继续输入"].exists)
            attachScreenshot(app, name: "\(mode) empty task marker and completed item")
            app.typeText("task-two")
            accessory.buttons["收起键盘"].tap()
            app.buttons["返回"].tap()
            XCTAssertTrue(file.waitForExistence(timeout: 15))
            file.tap()
            XCTAssertTrue(web.waitForExistence(timeout: 30))
            XCTAssertTrue(checks.element(boundBy: 0).waitForExistence(timeout: 10))
            XCTAssertEqual(checks.count, 2)
            XCTAssertEqual(String(describing: checks.element(boundBy: 0).value), completed)
            XCTAssertEqual(String(describing: checks.element(boundBy: 1).value), before)
            attachScreenshot(app, name: "\(mode) saved task completion")
            app.terminate()
        }
    }

    private func webToolbarControl(_ app: XCUIApplication, label: String) -> XCUIElement {
        // WebKit exposes aria-pressed format buttons as toggle controls.
        app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    func testMindMapIconMenusAboveKeyboard() {
        for mode in ["大纲", "思维导图"] {
            let app = makeApplication()
            app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
            app.launch()
            let file = app.staticTexts["Test Mind Map"].firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 15))
            file.tap()
            XCTAssertTrue(app.webViews["editor-ready"].waitForExistence(timeout: 30))
            app.webViews.buttons[mode].tap()
            let title = app.webViews.staticTexts["中心主题"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            if mode == "思维导图" { title.doubleTap() } else { title.tap() }
            let accessory = app.otherElements["mindmap-keyboard-accessory"].firstMatch
            XCTAssertTrue(accessory.waitForExistence(timeout: 10))
            for (control, command) in [("文字样式", "加粗"), ("列表", "无序列表"), ("代码", "代码块"), ("表格", "插入表格"), ("链接", "确认链接")] {
                let trigger = accessory.buttons[control]
                revealAccessoryButton(trigger, in: accessory)
                trigger.tap()
                let item = webToolbarControl(app, label: command)
                XCTAssertTrue(item.waitForExistence(timeout: 5))
                XCTAssertTrue(item.isHittable)
                XCTAssertGreaterThanOrEqual(item.frame.width, 36)
                XCTAssertGreaterThanOrEqual(item.frame.height, 44)
                XCTAssertLessThanOrEqual(item.frame.maxY, accessory.frame.minY)
                let palette = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", control + "操作")).firstMatch
                XCTAssertLessThanOrEqual(palette.frame.height, 60, "Secondary menus stay within a single compact row")
                XCTAssertFalse(app.webViews.staticTexts[control].exists, "Secondary menus omit category titles")
                XCTAssertFalse(app.webViews.staticTexts[command].exists, "Actions display icons while retaining accessible names")
                attachScreenshot(app, name: "\(mode) icon menu \(control)")
                app.webViews.buttons["关闭菜单"].tap()
                XCTAssertTrue(app.keyboards.firstMatch.exists, "Closing a palette retains text input")
            }
            app.terminate()
        }
    }

    func testMindMapInputInteractionStates() {
        checkMindMapInputInteractionStates(modes: ["大纲", "思维导图"])
    }

    func testMindMapEditingTextSelection() {
        checkMindMapInputInteractionStates(modes: ["思维导图"])
    }

    private func checkMindMapInputInteractionStates(modes: [String]) {
        for mode in modes {
            let app = makeApplication()
            app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
            app.launch()
            let all = app.buttons["all-documents"]
            XCTAssertTrue(all.waitForExistence(timeout: 15), app.debugDescription)
            all.tap()
            let file = app.staticTexts["Test Mind Map"].firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 15), app.debugDescription)
            file.tap()
            let web = app.webViews["editor-ready"]
            XCTAssertTrue(web.waitForExistence(timeout: 30))
            web.buttons[mode].tap()
            let title = web.staticTexts["中心主题"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            if mode == "大纲" {
                title.press(forDuration: 0.8)
                XCTAssertFalse(web.menuItems["编辑节点"].exists, "Outline never offers a long-press node menu")
                title.tap()
            } else {
                title.press(forDuration: 0.8)
                let edit = web.menuItems["编辑节点"]
                XCTAssertTrue(edit.waitForExistence(timeout: 5), app.debugDescription)
                web.menuItems["取消"].tap()
                title.doubleTap()
            }
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
            let label = mode == "大纲" ? "文档标题" : "节点正文"
            let field = web.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", label, label)).firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.press(forDuration: 0.8)
            XCTAssertFalse(web.menuItems["编辑节点"].exists, "Editing nodes preserve system text selection")
            XCTAssertTrue(keyboard.exists)
            let textActions = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["选择", "全选", "拷贝", "复制", "Select", "Select All", "Copy"]))
            XCTAssertTrue(textActions.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
            attachScreenshot(app, name: "\(mode) system text selection")
            if mode == "大纲" {
                let accessory = app.otherElements["mindmap-keyboard-accessory"].firstMatch
                for index in 0..<10 {
                    field.tap()
                    accessory.buttons["收起键盘"].tap()
                    let add = web.buttons["＋ 添加条目"]
                    if !add.isHittable { web.swipeUp() }
                    XCTAssertTrue(add.isHittable)
                    add.tap()
                    XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
                    let text = "visible-\(index)"
                    app.typeText(text)
                    let added = web.descendants(matching: .any).matching(NSPredicate(format: "(label == '节点正文' OR identifier == '节点正文') AND value CONTAINS %@", text)).firstMatch
                    XCTAssertTrue(added.waitForExistence(timeout: 5), app.debugDescription)
                    let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                        added.frame.minY >= web.frame.minY && added.frame.maxY <= accessory.frame.minY
                    }, object: added)
                    XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
                }
                attachScreenshot(app, name: "Outline new entry above keyboard")
            }
            app.terminate()
        }
    }

    func testMindMapToolbarAboveKeyboard() {
        for mode in ["大纲", "思维导图"] {
            let app = makeApplication()
            app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
            app.launch()
            let file = app.staticTexts["Test Mind Map"].firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 15))
            XCTAssertFalse(app.navigationBars.staticTexts["Test Documents"].exists, "The repository name is not shown as a screen heading")
            file.tap()
            XCTAssertTrue(app.webViews["editor-ready"].waitForExistence(timeout: 30))
            app.webViews.buttons[mode].tap()
            let title = app.webViews.staticTexts["中心主题"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
            if mode == "思维导图" { title.doubleTap() } else { title.tap() }
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 10), app.debugDescription)
            let accessory = app.otherElements["mindmap-keyboard-accessory"].firstMatch
            XCTAssertTrue(accessory.waitForExistence(timeout: 10), app.debugDescription)
            let style = accessory.buttons["文字样式"]
            XCTAssertTrue(style.waitForExistence(timeout: 10))
            XCTAssertTrue(accessory.frame.contains(style.frame), "Formatting lives inside the system input accessory")
            XCTAssertLessThanOrEqual(accessory.frame.maxY, keyboard.frame.minY)
            let fieldLabel = mode == "思维导图" ? "节点正文" : "文档标题"
            let field = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", fieldLabel, fieldLabel)).firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertLessThanOrEqual(field.frame.maxY, accessory.frame.minY, "The editing node remains above the input accessory")
            field.press(forDuration: 0.8)
            XCTAssertFalse(app.webViews.menuItems["编辑节点"].exists, "Long pressing editable text must preserve native text selection")
            XCTAssertTrue(keyboard.exists, "Text selection must retain the keyboard")
            field.tap()
            attachScreenshot(app, name: "\(mode) native keyboard accessory")
            app.typeText(".")
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "."), object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
            let typedValue = field.value as? String ?? ""
            XCTAssertEqual(typedValue.replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespacesAndNewlines), "中心主题")
            let undo = accessory.buttons["撤销"], redo = accessory.buttons["重做"]
            revealAccessoryButton(undo, in: accessory)
            undo.tap()
            let reverted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "中心主题"), object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [reverted], timeout: 5), .completed)
            revealAccessoryButton(redo, in: accessory)
            redo.tap()
            let redone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", typedValue), object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [redone], timeout: 5), .completed)
            revealAccessoryButton(undo, in: accessory)
            undo.tap()
            revealAccessoryButton(style, in: accessory)
            for (control, command) in [("列表", "无序列表"), ("表格", "插入表格"), ("代码", "代码块"), ("链接", "确认链接")] {
                let button = accessory.buttons[control]
                revealAccessoryButton(button, in: accessory)
                button.tap()
                let item = webToolbarControl(app, label: command)
                XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
                attachScreenshot(app, name: "\(mode) \(control) contextual menu")
                XCTAssertTrue(item.isHittable, "Native controls must open a visible usable panel: \(item.debugDescription)\n\(app.debugDescription)")
                XCTAssertLessThanOrEqual(item.frame.maxY, accessory.frame.minY)
                if control == "列表" {
                    for listStyle in ["无序列表", "有序列表", "待办列表"] {
                        let option = webToolbarControl(app, label: listStyle)
                        XCTAssertTrue(option.isHittable, "Every list style must be usable above the native keyboard")
                        XCTAssertLessThanOrEqual(option.frame.maxY, accessory.frame.minY)
                    }
                }
                XCTAssertTrue(app.webViews.buttons["关闭菜单"].isHittable)
                app.webViews.buttons["关闭菜单"].tap()
                XCTAssertTrue(keyboard.exists, "Closing a menu must retain text input")
                XCTAssertTrue(accessory.exists)
            }
            XCTAssertFalse(app.webViews.buttons["文字样式"].isHittable, "The old web toolbar must remain hidden")
            revealAccessoryButton(style, in: accessory)
            style.tap()
            let bold = webToolbarControl(app, label: "加粗")
            XCTAssertTrue(bold.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertGreaterThanOrEqual(bold.frame.width, 36)
            XCTAssertGreaterThanOrEqual(bold.frame.height, 44)
            attachScreenshot(app, name: "\(mode) compact text formatting")
            bold.tap()
            XCTAssertTrue(keyboard.exists, "Formatting must retain the keyboard")
            let nextKeyboard = app.buttons["Next keyboard"]
            if nextKeyboard.exists && nextKeyboard.isHittable {
                nextKeyboard.tap()
                XCTAssertTrue(accessory.exists)
                XCTAssertTrue(style.isHittable)
                attachScreenshot(app, name: "\(mode) switched input method")
            }
            let image = accessory.buttons["插入图片"]
            revealAccessoryButton(image, in: accessory)
            image.tap()
            let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == '取消'")).firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
            attachScreenshot(app, name: "\(mode) native image picker")
            cancel.tap()
            // UIKit may dismiss the keyboard while presenting the Files picker.
            if !accessory.waitForExistence(timeout: 5) { field.tap() }
            XCTAssertTrue(accessory.waitForExistence(timeout: 5))
            XCTAssertFalse(accessory.buttons["备注"].exists)
            XCTAssertFalse(accessory.buttons["节点操作"].exists)
            revealAccessoryButton(style, in: accessory)
            style.tap()
            let quote = webToolbarControl(app, label: "引用")
            XCTAssertTrue(quote.waitForExistence(timeout: 5), app.debugDescription)
            quote.tap()
            XCTAssertTrue(keyboard.exists)
            app.typeText("quote text")
            XCTAssertTrue(field.value as? String != nil)
            let dismiss = accessory.buttons["收起键盘"]
            XCTAssertTrue(dismiss.isHittable)
            dismiss.tap()
            let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: keyboard)
            XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
            attachScreenshot(app, name: "\(mode) keyboard dismissed")
        }
    }

    func testMindMapBlocksAndSelectionToolbar() {
        verifyMindMapBlocks(includeNodeActions: true, modes: ["思维导图"])
    }

    func testMindMapBlocksContinueWithoutHelper() {
        verifyMindMapBlocks(includeNodeActions: false, modes: ["大纲"])
    }

    private func verifyMindMapBlocks(includeNodeActions: Bool, modes: [String] = ["大纲", "思维导图"]) {
        for mode in modes {
            let app = makeApplication()
            app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
            app.launch()
            let file = app.staticTexts["Test Mind Map"].firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 15))
            file.tap()
            XCTAssertTrue(app.webViews["editor-ready"].waitForExistence(timeout: 30))
            app.webViews.buttons[mode].tap()
            let title = app.webViews.staticTexts["中心主题"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            if mode == "思维导图" { title.doubleTap() } else { title.tap() }
            let accessory = app.otherElements["mindmap-keyboard-accessory"].firstMatch
            XCTAssertTrue(accessory.waitForExistence(timeout: 10))
            app.typeText("\n\nblock-node")
            let label = "节点正文"
            let field = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", label, label)).firstMatch
            let table = accessory.buttons["表格"]
            revealAccessoryButton(table, in: accessory)
            table.tap()
            let insert = app.webViews.buttons["插入表格"]
            XCTAssertTrue(insert.waitForExistence(timeout: 5))
            insert.tap()
            // Insertion preserves the text cursor after the table. Tap its first cell
            // to exercise continuation from inside the block itself.
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.30)).tap()
            app.typeText("cell text")
            XCTAssertFalse(app.webViews.buttons["在块后继续输入"].exists)
            // Tap the reserved paragraph beneath the table to continue typing.
            if mode == "思维导图" {
                let visible = field.frame.intersection(app.webViews.firstMatch.frame)
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX, dy: field.frame.maxY - 24)).tap()
            } else {
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.98)).tap()
            }
            app.typeText("after table")
            let tableText = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "after table"), object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [tableText], timeout: 5), .completed)
            XCTAssertTrue(app.webViews.staticTexts["cell text"].firstMatch.exists, "Continuation must leave the table cell")
            let code = accessory.buttons["代码"]
            revealAccessoryButton(code, in: accessory)
            code.tap()
            webToolbarControl(app, label: "代码块").tap()
            app.typeText(" code text")
            app.typeText("\n\nafter code")
            XCTAssertFalse(app.webViews.buttons["在块后继续输入"].exists)
            let codeText = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "after code"), object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [codeText], timeout: 5), .completed)
            attachScreenshot(app, name: "\(mode) text after table and code")
            if !includeNodeActions { app.terminate(); continue }
            accessory.buttons["收起键盘"].tap()
            app.webViews.staticTexts["中心主题"].firstMatch.tap()
            let child = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "添加子节点")).firstMatch
            XCTAssertTrue(child.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(app.webViews.buttons["编辑节点"].firstMatch.isHittable)
            attachScreenshot(app, name: "\(mode) selected node action bar")
            child.tap()
            let newField = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", "节点正文", "节点正文")).firstMatch
            XCTAssertTrue(newField.waitForExistence(timeout: 5), app.debugDescription)
            if !accessory.exists { newField.tap() }
            XCTAssertTrue(accessory.waitForExistence(timeout: 5))
            app.typeText("Selected Child")
            let childField = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "(label == %@ OR identifier == %@) AND value CONTAINS %@", "节点正文", "节点正文", "Selected Child")).firstMatch
            XCTAssertTrue(childField.waitForExistence(timeout: 5), app.debugDescription)
            accessory.buttons["收起键盘"].tap()
            let childNode = app.webViews.staticTexts["Selected Child"].firstMatch
            childNode.tap()
            app.webViews.buttons["更多节点操作"].tap()
            let delete = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "删除节点")).firstMatch
            XCTAssertTrue(delete.waitForExistence(timeout: 5))
            delete.tap()
            let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: childNode)
            XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
        }
    }

    func testAllDocumentsAndBottomSearch() {
        let app = makeApplication()
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "browser"
        app.launch()
        XCTAssertTrue(app.staticTexts["Test Canvas"].firstMatch.waitForExistence(timeout: 15))
        let all = app.buttons["all-documents"]
        let search = app.textFields["browser-search"]
        XCTAssertTrue(all.waitForExistence(timeout: 15))
        XCTAssertTrue(search.isHittable)
        XCTAssertTrue(app.buttons["browser-create"].isHittable)
        attachScreenshot(app, name: "Folders with bottom actions")

        // Folder-page search includes documents in deeper directories.
        search.tap()
        search.typeText("Nested Idea")
        XCTAssertTrue(app.staticTexts["Nested Idea"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Test Canvas"].exists)
        app.buttons["清除搜索"].tap()
        all.tap()
        XCTAssertTrue(app.staticTexts["Test Canvas"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nested Idea"].firstMatch.exists)
        XCTAssertTrue(app.buttons["browser-create"].isHittable)
        attachScreenshot(app, name: "All documents with bottom actions")
        search.tap()
        search.typeText("Test Mind")
        XCTAssertTrue(app.staticTexts["Test Mind Map"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Test Canvas"].exists)
        XCTAssertFalse(app.staticTexts["Nested Idea"].exists)
        app.buttons["清除搜索"].tap()
        XCTAssertTrue(app.staticTexts["Nested Idea"].firstMatch.exists)
    }

    func testNewMindMapDoesNotReusePreviouslyOpenedDocument() {
        let app = makeApplication()
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "browser"
        app.launch()
        let original = app.staticTexts["Test Mind Map"].firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 15))
        original.tap()
        let web = app.webViews["editor-ready"]
        XCTAssertTrue(web.waitForExistence(timeout: 30))
        web.buttons["大纲"].tap()
        web.staticTexts["中心主题"].firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        app.typeText("original-only")
        app.buttons["返回"].tap()
        XCTAssertTrue(original.waitForExistence(timeout: 15))

        // Reopen without editing before creating, matching the reported trigger.
        original.tap()
        XCTAssertTrue(web.staticTexts.matching(NSPredicate(format: "label CONTAINS 'original-only'")).firstMatch.waitForExistence(timeout: 15))
        app.buttons["返回"].tap()
        XCTAssertTrue(app.buttons["browser-create"].waitForExistence(timeout: 10))
        app.buttons["browser-create"].tap()
        app.buttons["新建思维导图"].tap()
        XCTAssertTrue(web.staticTexts["中心主题"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(web.staticTexts.matching(NSPredicate(format: "label CONTAINS 'original-only'")).firstMatch.exists)
        attachScreenshot(app, name: "New independent blank mind map")
        web.buttons["大纲"].tap()
        web.staticTexts["中心主题"].firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        app.typeText("new-only")
        app.buttons["返回"].tap()
        let created = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Untitled-'")).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 15))
        for (file, included, excluded) in [(original, "original-only", "new-only"), (created, "new-only", "original-only")] {
            file.tap()
            XCTAssertTrue(web.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", included)).firstMatch.waitForExistence(timeout: 15))
            XCTAssertFalse(web.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", excluded)).firstMatch.exists)
            app.buttons["返回"].tap()
            XCTAssertTrue(app.buttons["browser-create"].waitForExistence(timeout: 10))
        }
    }

    func testCreateFromFolderPageAndAllDocuments() {
        let app = makeApplication()
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "browser"
        app.launch()
        XCTAssertTrue(app.staticTexts["Test Canvas"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["browser-create"].waitForExistence(timeout: 15))
        app.buttons["browser-create"].tap()
        app.buttons["新建画布"].tap()
        XCTAssertTrue(app.webViews["editor-ready"].waitForExistence(timeout: 30))
        app.buttons["返回"].tap()
        let created = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Untitled-'")).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 10), "Folder-page creation saves into the root")
        app.buttons["all-documents"].tap()
        app.buttons["browser-create"].tap()
        app.buttons["新建思维导图"].tap()
        XCTAssertTrue(app.webViews["editor-ready"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.webViews.staticTexts["中心主题"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["返回"].tap()
        XCTAssertTrue(app.buttons["browser-create"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Untitled-'")).count, 2)
    }

    func testNestedFolderSearchAndCreation() {
        let app = makeApplication()
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "browser"
        app.launch()
        XCTAssertTrue(app.staticTexts["Test Canvas"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Projects"].firstMatch.waitForExistence(timeout: 15))
        app.staticTexts["Projects"].firstMatch.tap()
        app.staticTexts["Nested"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Nested Idea"].firstMatch.waitForExistence(timeout: 5))
        let search = app.textFields["browser-search"]
        XCTAssertTrue(search.isHittable)
        search.tap()
        search.typeText("missing")
        XCTAssertFalse(app.staticTexts["Nested Idea"].exists)
        app.buttons["清除搜索"].tap()
        XCTAssertTrue(app.staticTexts["Nested Idea"].exists)
        app.buttons["browser-create"].tap()
        app.buttons["新建思维导图"].tap()
        XCTAssertTrue(app.webViews["editor-ready"].waitForExistence(timeout: 30))
        app.buttons["返回"].tap()
        let created = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Untitled-'")).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 10), "Creation saves into the nested folder")
        attachScreenshot(app, name: "Nested folder with bottom actions")
    }

    func testLargeMindMapEditingGesturesAndSave() {
        for mode in ["大纲", "思维导图"] {
            let app = makeApplication()
            app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
            app.launchEnvironment["SIYE_UI_TEST_LARGE_MAP"] = "1"
            app.launch()
            let file = app.staticTexts["Test Mind Map"].firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 15))
            let openStarted = Date()
            file.tap()
            let web = app.webViews["editor-ready"]
            XCTAssertTrue(web.waitForExistence(timeout: 30))
            print("DEVICE_LARGE_MAP open-to-ready \(mode): \(Date().timeIntervalSince(openStarted))s (includes XCTest overhead)")
            web.buttons[mode].tap()
            let title = web.staticTexts["中心主题"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            if mode == "思维导图" { title.doubleTap() } else { title.tap() }
            let accessory = app.otherElements["mindmap-keyboard-accessory"].firstMatch
            XCTAssertTrue(accessory.waitForExistence(timeout: 10))
            let label = mode == "思维导图" ? "节点正文" : "文档标题"
            let field = web.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", label, label)).firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            let marker = "device-save-1234567890"
            app.typeText(marker)
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", marker), object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
            attachScreenshot(app, name: "1000 nodes \(mode) input")
            accessory.buttons["收起键盘"].tap()
            if mode == "思维导图" {
                web.pinch(withScale: 0.7, velocity: -1)
                web.pinch(withScale: 1.3, velocity: 1)
                web.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.7)).press(forDuration: 0.05, thenDragTo: web.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
            } else {
                web.swipeUp()
                web.swipeDown()
            }
            attachScreenshot(app, name: "1000 nodes \(mode) gestures")
            app.buttons["返回"].tap()
            XCTAssertTrue(file.waitForExistence(timeout: 15))
            file.tap()
            XCTAssertTrue(web.waitForExistence(timeout: 30))
            web.buttons["大纲"].tap()
            XCTAssertTrue(web.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch.waitForExistence(timeout: 10), "Returning and reopening must retain the latest input")
            attachScreenshot(app, name: "1000 nodes \(mode) persisted input")
            app.terminate()
        }
    }

    func testChineseNineKeyCompositionAndSave() throws {
        let app = makeApplication()
        app.launchEnvironment["SIYE_UI_TEST_FIXTURE"] = "documents"
        app.launch()
        let file = app.staticTexts["Test Mind Map"].firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15))
        file.tap()
        let web = app.webViews["editor-ready"]
        XCTAssertTrue(web.waitForExistence(timeout: 30))
        web.buttons["大纲"].tap()
        web.staticTexts["中心主题"].firstMatch.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        let letters = ["M N O", "G H I", "G H I", "A B C", "M N O"]
        let firstKey = keyboard.keys.matching(NSPredicate(format: "label CONTAINS[c] %@", letters[0])).firstMatch
        guard firstKey.exists else {
            throw XCTSkip("The active keyboard does not expose Chinese nine-key letter keys; input method settings are left unchanged")
        }
        for letters in letters {
            let key = keyboard.keys.matching(NSPredicate(format: "label CONTAINS[c] %@", letters)).firstMatch
            XCTAssertTrue(key.exists, keyboard.debugDescription)
            key.tap()
        }
        let candidate = app.cells["你好"].firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 5), app.debugDescription)
        candidate.tap()
        let field = web.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", "文档标题", "文档标题")).firstMatch
        let committed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "你好"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [committed], timeout: 5), .completed)
        attachScreenshot(app, name: "Chinese nine-key committed candidate")
        app.otherElements["mindmap-keyboard-accessory"].firstMatch.buttons["收起键盘"].tap()
        app.buttons["返回"].tap()
        XCTAssertTrue(file.waitForExistence(timeout: 15))
        file.tap()
        XCTAssertTrue(web.waitForExistence(timeout: 30))
        web.buttons["大纲"].tap()
        XCTAssertTrue(web.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "你好")).firstMatch.waitForExistence(timeout: 10))
    }

    func testReleaseLaunchSmoke() throws {
#if DEBUG
        throw XCTSkip("Run the normal-configuration startup check with a Release build")
#else
        let app = makeApplication()
        app.launch()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["browser-create"].exists || app.buttons["选择文件夹"].exists || app.webViews["editor-ready"].exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, app.debugDescription)
        attachScreenshot(app, name: "Release launch on device")
#endif
    }

    private func revealAccessoryButton(_ button: XCUIElement, in accessory: XCUIElement) {
        if !button.isHittable { accessory.scrollViews.firstMatch.swipeLeft() }
        if !button.isHittable { accessory.scrollViews.firstMatch.swipeRight() }
        XCTAssertTrue(button.isHittable)
    }

    private func makeApplication() -> XCUIApplication {
        let app = XCUIApplication()
        // Older simulator runtimes keep the WebKit Swift overlay in their Cryptex.
        let environment = ProcessInfo.processInfo.environment
        if let root = environment["SIMULATOR_ROOT"] ?? environment["DYLD_ROOT_PATH"] {
            let libraryPath = root + "/System/Cryptexes/OS/usr/lib/swift"
            if FileManager.default.fileExists(atPath: libraryPath + "/libswiftWebKit.dylib") {
                app.launchEnvironment["DYLD_FALLBACK_LIBRARY_PATH"] = libraryPath
            }
        }
        return app
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
