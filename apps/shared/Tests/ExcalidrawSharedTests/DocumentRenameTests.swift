import Foundation
import XCTest
@testable import ExcalidrawShared

final class DocumentRenameTests: XCTestCase {
    func testRepeatedRenameRedirectsLateSavesAndKeepsCurrentEntry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = FolderSourceStore(userDefaults: defaults, indexStore: ExcalidrawJSONFileIndexStore(fileURL: root.appendingPathComponent("index.json")))
        let manager = DocumentManager(store: store)
        let originalURL = root.appendingPathComponent("drawing.excalidraw")
        try Data("{\"elements\":[]}".utf8).write(to: originalURL)
        let entry = try XCTUnwrap(store.upsertEntry(for: originalURL, folderId: UUID(), rootURL: root, lastOpenedAt: Date()))
        _ = try manager.open(entry: entry)
        let done = expectation(description: "Queued and late saves complete")
        done.expectedFulfillmentCount = 2
        let checkSave: (Result<ExcalidrawFileEntry, Error>) -> Void = { result in
            if case .success(let saved) = result {
                XCTAssertEqual(saved.fileName, "final.excalidraw")
                XCTAssertEqual(saved.id, entry.id)
            } else {
                XCTFail("Save failed: \(result)")
            }
            done.fulfill()
        }
        manager.saveScene(docId: originalURL.path, sceneJson: ["elements": []], completion: checkSave)
        try manager.renameCurrentEntry(to: "renamed")
        try manager.renameCurrentEntry(to: "final")
        try manager.renameCurrentEntry(to: "final")
        XCTAssertEqual(manager.currentEntry?.fileName, "final.excalidraw")
        manager.saveScene(docId: originalURL.path, sceneJson: ["elements": [], "marker": "latest"], completion: checkSave)
        wait(for: [done], timeout: 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("renamed.excalidraw").path))
        let data = try Data(contentsOf: root.appendingPathComponent("final.excalidraw"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["marker"] as? String, "latest")
        XCTAssertEqual(manager.currentEntry?.fileName, "final.excalidraw")
    }
}
