import Foundation
import XCTest
@testable import ExcalidrawShared

final class IndexPersistenceWriterTests: XCTestCase {
    private final class BlockingStore: ExcalidrawFileIndexStore {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished: XCTestExpectation
        var batches: [[ExcalidrawFileEntry]] = []
        init(finished: XCTestExpectation) { self.finished = finished }
        func loadEntries() throws -> [ExcalidrawFileEntry] { [] }
        func saveEntries(_ entries: [ExcalidrawFileEntry]) throws {
            XCTAssertFalse(Thread.isMainThread)
            batches.append(entries)
            if batches.count == 1 {
                entered.signal()
                _ = release.wait(timeout: .now() + 5)
            } else { finished.fulfill() }
        }
    }

    func testPendingWritesCoalesceAndPersistLatestSnapshotOffMain() {
        let done = expectation(description: "Latest snapshot written")
        let store = BlockingStore(finished: done), writer = IndexPersistenceWriter(store: store)
        let entry = ExcalidrawFileEntry(folderId: UUID(), relativePath: "a.mindmap", fileName: "a.mindmap", fileURL: URL(fileURLWithPath: "/tmp/a.mindmap"), modifiedAt: Date(), fileSize: 1)
        writer.schedule([])
        XCTAssertEqual(store.entered.wait(timeout: .now() + 5), .success)
        writer.schedule([entry]); writer.schedule([]); writer.schedule([entry, entry])
        store.release.signal()
        wait(for: [done], timeout: 5)
        XCTAssertEqual(store.batches.count, 2)
        XCTAssertEqual(store.batches.last?.count, 2)
    }
}
