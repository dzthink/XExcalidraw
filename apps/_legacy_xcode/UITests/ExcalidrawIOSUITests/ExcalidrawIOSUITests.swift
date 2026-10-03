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
            for listStyle in ["无序列表", "有序列表", "短横线列表", "无序列表", "退出列表"] {
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
            attachScreenshot(app, name: "\(mode) list conversion")
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
                    for listStyle in ["无序列表", "有序列表", "短横线列表", "退出列表"] {
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

    func testMindMapBlocksAndLongPressMenu() {
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
            let label = mode == "思维导图" ? "节点正文" : "文档标题"
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
            let after = app.webViews.buttons["在块后继续输入"]
            XCTAssertTrue(after.waitForExistence(timeout: 5), app.debugDescription)
            after.tap()
            app.typeText("after table")
            let tableText = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "after table"), object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [tableText], timeout: 5), .completed)
            XCTAssertTrue(app.webViews.staticTexts["cell text"].firstMatch.exists, "Continuation must leave the table cell")
            let code = accessory.buttons["代码"]
            revealAccessoryButton(code, in: accessory)
            code.tap()
            webToolbarControl(app, label: "代码块").tap()
            app.typeText(" code text")
            XCTAssertTrue(after.waitForExistence(timeout: 5))
            after.tap()
            app.typeText("after code")
            let codeText = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "after code"), object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [codeText], timeout: 5), .completed)
            attachScreenshot(app, name: "\(mode) text after table and code")
            accessory.buttons["收起键盘"].tap()
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.04)).press(forDuration: 0.8)
            let child = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "添加子节点")).firstMatch
            XCTAssertTrue(child.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "删除节点")).firstMatch.isHittable)
            attachScreenshot(app, name: "\(mode) long press node menu")
            child.tap()
            let newField = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", "节点正文", "节点正文")).firstMatch
            XCTAssertTrue(newField.waitForExistence(timeout: 5), app.debugDescription)
            if !accessory.exists { newField.tap() }
            XCTAssertTrue(accessory.waitForExistence(timeout: 5))
            app.typeText("Long Press Child")
            let childField = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "(label == %@ OR identifier == %@) AND value CONTAINS %@", "节点正文", "节点正文", "Long Press Child")).firstMatch
            XCTAssertTrue(childField.waitForExistence(timeout: 5), app.debugDescription)
            accessory.buttons["收起键盘"].tap()
            childField.press(forDuration: 0.8)
            let delete = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "删除节点")).firstMatch
            XCTAssertTrue(delete.waitForExistence(timeout: 5))
            delete.tap()
            let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: childField)
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
