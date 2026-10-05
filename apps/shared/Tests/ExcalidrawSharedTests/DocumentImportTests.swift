import XCTest
@testable import ExcalidrawShared

final class DocumentImportTests: XCTestCase {
    func testRepeatedImportCreatesEditableMindMapsWithoutOverwritingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repository = root.appendingPathComponent("Repository")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FolderSourceStore(userDefaults: defaults, indexStore: ExcalidrawJSONFileIndexStore(fileURL: root.appendingPathComponent("index.json")))
        let manager = DocumentManager(store: store, draftDirectory: root.appendingPathComponent("drafts"))
        try manager.addFolder(url: repository)
        let ready = expectation(description: "Source ready")
        DispatchQueue.main.async { ready.fulfill() }
        wait(for: [ready], timeout: 3)
        let source = root.appendingPathComponent("示例.mm")
        try Data("<map><node TEXT=\"中心\"><node TEXT=\"子主题\"/></node></map>".utf8).write(to: source)
        let original = repository.appendingPathComponent("示例.mindmap")
        let originalBytes = Data("existing file".utf8)
        try originalBytes.write(to: original)
        var importedURLs = Set<URL>()
        for _ in 0..<2 {
            let imported = expectation(description: "Imported")
            manager.importScene(from: source) { result in
                do {
                    let entry = try result.get()
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertEqual(entry.fileURL.pathExtension, "mindmap")
                    XCTAssertNotEqual(entry.fileURL, original)
                    XCTAssertTrue(importedURLs.insert(entry.fileURL).inserted)
                    let doc = try JSONSerialization.jsonObject(with: Data(contentsOf: entry.fileURL)) as? [String: Any]
                    XCTAssertEqual(doc?["format"] as? String, "siye-mindmap")
                    XCTAssertEqual(manager.currentEntry?.id, entry.id)
                } catch { XCTFail("Import failed: \(error)") }
                imported.fulfill()
            }
            wait(for: [imported], timeout: 3)
        }
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
    }
}
