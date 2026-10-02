import Foundation
import XCTest
@testable import ExcalidrawShared

final class DocumentCreationTests: XCTestCase {
    func testCreationUsesRootOrNestedDirectoryAndKeepsRelativeIndexPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repository = root.appendingPathComponent("Repository", isDirectory: true)
        let nested = repository.appendingPathComponent("Projects/Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FolderSourceStore(userDefaults: defaults, indexStore: ExcalidrawJSONFileIndexStore(fileURL: root.appendingPathComponent("index.json")))
        let manager = DocumentManager(store: store)
        try manager.addFolder(url: repository)
        let sourceId = try XCTUnwrap(store.activeSourceId)
        let sourceReady = expectation(description: "Source published")
        DispatchQueue.main.async { sourceReady.fulfill() }
        wait(for: [sourceReady], timeout: 3)

        var createdURLs = Set<URL>()
        for (path, type) in [("", SiyeDocumentType.excalidraw), ("Projects/Nested", .mindmap), ("Projects/Nested", .mindmap)] {
            let created = expectation(description: "Document created")
            manager.createBlankDocument(in: sourceId, relativeFolderPath: path, type: type) { result in
                XCTAssertTrue(Thread.isMainThread)
                do {
                    let scene = try result.get()
                    let entry = try XCTUnwrap(manager.currentEntry)
                    XCTAssertEqual(scene.docId, entry.fileURL.path)
                    XCTAssertEqual(entry.folderId, sourceId)
                    XCTAssertEqual(entry.fileURL.deletingLastPathComponent().standardizedFileURL, (path.isEmpty ? repository : nested).standardizedFileURL)
                    XCTAssertEqual(entry.relativePath, path.isEmpty ? entry.fileName : path + "/" + entry.fileName)
                    XCTAssertEqual(SiyeDocumentType(fileName: entry.fileName), type)
                    XCTAssertTrue(createdURLs.insert(entry.fileURL).inserted, "Repeated creation must not overwrite an existing file")
                    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: entry.fileURL)) as? [String: Any]
                    XCTAssertNotNil(json)
                    if type == .mindmap { XCTAssertEqual(json?["format"] as? String, "siye-mindmap") }
                } catch {
                    XCTFail("Creation failed: \(error)")
                }
                created.fulfill()
            }
            wait(for: [created], timeout: 3)
        }
    }
}
