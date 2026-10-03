import Foundation
import XCTest
@testable import ExcalidrawShared

final class DocumentSaveTests: XCTestCase {
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
