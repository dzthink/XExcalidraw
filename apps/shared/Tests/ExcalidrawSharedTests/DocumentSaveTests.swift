import Foundation
import XCTest
@testable import ExcalidrawShared

final class DocumentSaveTests: XCTestCase {
    func testOldCanvasSaveAfterCreatingDocumentKeepsDocumentsIndependent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repository = root.appendingPathComponent("Repository", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FolderSourceStore(userDefaults: defaults, indexStore: ExcalidrawJSONFileIndexStore(fileURL: root.appendingPathComponent("index.json")))
        let manager = DocumentManager(store: store, draftDirectory: root.appendingPathComponent("drafts"))
        try manager.addFolder(url: repository)
        let sourceReady = expectation(description: "Source published")
        DispatchQueue.main.async { sourceReady.fulfill() }
        wait(for: [sourceReady], timeout: 3)

        var scenes: [DocumentScene] = []
        for _ in 0..<2 {
            let created = expectation(description: "Mind map created")
            manager.createBlankDocument(type: .mindmap) { result in
                do { scenes.append(try result.get()) } catch { XCTFail(error.localizedDescription) }
                created.fulfill()
            }
            wait(for: [created], timeout: 3)
        }
        let old = scenes[0], new = scenes[1]
        let newEntry = try XCTUnwrap(manager.currentEntry)
        let blankData = try Data(contentsOf: newEntry.fileURL)
        let oldSaved = expectation(description: "Old canvas flush acknowledged")
        // The WebView still contains the old document when creation activates the new file.
        manager.saveScene(docId: old.docId, sceneJson: ["marker": "old edit"]) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            XCTAssertEqual(manager.currentEntry?.id, newEntry.id)
            oldSaved.fulfill()
        }
        wait(for: [oldSaved], timeout: 3)
        XCTAssertEqual(try Data(contentsOf: newEntry.fileURL), blankData)
        let newSaved = expectation(description: "New document saved independently")
        manager.saveScene(docId: new.docId, sceneJson: ["marker": "new edit"]) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            XCTAssertEqual(manager.currentEntry?.id, newEntry.id)
            newSaved.fulfill()
        }
        wait(for: [newSaved], timeout: 3)
        for (scene, marker) in [(old, "old edit"), (new, "new edit")] {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: scene.docId))) as? [String: String]
            XCTAssertEqual(json?["marker"], marker)
        }
    }

    func testRawBridgeJSONSavesAndInvalidJSONDoesNotReplaceDocument() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FolderSourceStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!, indexStore: ExcalidrawJSONFileIndexStore(fileURL: root.appendingPathComponent("index.json")))
        let manager = DocumentManager(store: store), url = root.appendingPathComponent("a.mindmap")
        try Data("{}".utf8).write(to: url)
        let entry = try XCTUnwrap(store.upsertEntry(for: url, folderId: UUID(), rootURL: root))
        manager.activate(entry: entry)
        let saved = expectation(description: "Raw JSON saved")
        manager.saveScene(docId: url.path, sceneJson: "{\"marker\":\"latest\"}") { result in
            XCTAssertTrue(Thread.isMainThread)
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            saved.fulfill()
        }
        wait(for: [saved], timeout: 5)
        let data = try Data(contentsOf: url)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: data) as? [String: String])?["marker"], "latest")
        let rejected = expectation(description: "Invalid JSON rejected")
        manager.saveScene(docId: url.path, sceneJson: "invalid JSON") { result in
            if case .success = result { XCTFail("Invalid JSON accepted") }
            rejected.fulfill()
        }
        wait(for: [rejected], timeout: 5)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
    func testLateSaveDoesNotActivateThePreviouslyOpenDocument() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FolderSourceStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!, indexStore: ExcalidrawJSONFileIndexStore(fileURL: root.appendingPathComponent("index.json")))
        let manager = DocumentManager(store: store), folderID = UUID()
        let firstURL = root.appendingPathComponent("first.mindmap"), secondURL = root.appendingPathComponent("second.mindmap")
        try Data("{}".utf8).write(to: firstURL)
        try Data("{}".utf8).write(to: secondURL)
        let first = try XCTUnwrap(store.upsertEntry(for: firstURL, folderId: folderID, rootURL: root))
        let second = try XCTUnwrap(store.upsertEntry(for: secondURL, folderId: folderID, rootURL: root))
        manager.activate(entry: first)
        let saved = expectation(description: "Previous document saved")
        manager.saveScene(docId: firstURL.path, sceneJson: "{\"saved\":true}") { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            XCTAssertEqual(manager.currentEntry?.id, second.id)
            saved.fulfill()
        }
        manager.activate(entry: second)
        wait(for: [saved], timeout: 5)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(contentsOf: firstURL)) as? [String: Bool])?["saved"], true)
        XCTAssertEqual(try Data(contentsOf: secondURL), Data("{}".utf8))
    }

}
