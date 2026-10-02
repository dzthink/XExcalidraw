import Foundation
import XCTest
@testable import ExcalidrawShared

final class DocumentReadTests: XCTestCase {
    func testAsyncReadReturnsOnMainWithoutActivatingOrChangingFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = FolderSourceStore(userDefaults: defaults, indexStore: ExcalidrawJSONFileIndexStore(fileURL: root.appendingPathComponent("index.json")))
        let manager = DocumentManager(store: store)
        let url = root.appendingPathComponent("drawing.excalidraw")
        let original = Data("{\"elements\":[{\"id\":\"preserved\"}],\"appState\":{}}".utf8)
        try original.write(to: url)
        let entry = ExcalidrawFileEntry(folderId: UUID(), relativePath: url.lastPathComponent, fileName: url.lastPathComponent, fileURL: url, modifiedAt: Date(), fileSize: Int64(original.count))
        let done = expectation(description: "Read completed")
        manager.read(entry: entry) { result in
            XCTAssertTrue(Thread.isMainThread)
            guard case .success(let scene) = result else { XCTFail("Read failed"); done.fulfill(); return }
            XCTAssertEqual(scene.docId, url.path)
            XCTAssertNil(manager.currentEntry)
            XCTAssertEqual(try? Data(contentsOf: url), original)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }
}
