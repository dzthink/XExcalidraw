import Foundation
import XCTest
@testable import ExcalidrawShared

final class MindMapAttachmentStoreTests: XCTestCase {
    func testCustomDirectoryPreservesOldAttachmentsAndRejectsTraversal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let document = root.appendingPathComponent("plan.mindmap")
        let bytes = Data([1, 2, 3])
        let old = try MindMapAttachmentStore.save(imageData: bytes, mimeType: "image/png", documentURL: document, repositoryURL: root, directoryName: "attachments")
        let new = try MindMapAttachmentStore.save(imageData: bytes, mimeType: "image/png", documentURL: document, repositoryURL: root, directoryName: "assets/images")
        let allowed = ["attachments", "assets/images"]
        XCTAssertNotNil(MindMapAttachmentStore.resolve(relativePath: old, documentURL: document, repositoryURL: root, allowedDirectories: allowed))
        XCTAssertNotNil(MindMapAttachmentStore.resolve(relativePath: new, documentURL: document, repositoryURL: root, allowedDirectories: allowed))
        XCTAssertThrowsError(try MindMapAttachmentStore.save(imageData: bytes, mimeType: "image/png", documentURL: document, repositoryURL: root, directoryName: "../outside"))
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        XCTAssertTrue(EditorPreferences.setAttachmentDirectory("assets/images", defaults: defaults))
        XCTAssertTrue(EditorPreferences.setAttachmentDirectory("图片", defaults: defaults))
        XCTAssertTrue(EditorPreferences.attachmentDirectories(defaults: defaults).contains("assets/images"))
        XCTAssertFalse(EditorPreferences.setAttachmentDirectory("/tmp/images", defaults: defaults))
        XCTAssertEqual(EditorPreferences.attachmentDirectory(defaults: defaults), "图片")
    }

    func testSavesImageInRepositoryAndReturnsDocumentRelativePath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let documentDirectory = root.appendingPathComponent("ideas/2026", isDirectory: true)
        try FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)
        let document = documentDirectory.appendingPathComponent("plan.mindmap")
        let image = Data([0x89, 0x50, 0x4e, 0x47])

        let path = try MindMapAttachmentStore.save(
            imageData: image,
            mimeType: "image/png",
            documentURL: document,
            repositoryURL: root
        )

        XCTAssertTrue(path.hasPrefix("../../attachments/"))
        let resolved = try XCTUnwrap(MindMapAttachmentStore.resolve(
            relativePath: path,
            documentURL: document,
            repositoryURL: root
        ))
        XCTAssertEqual(try Data(contentsOf: resolved), image)
        XCTAssertNil(MindMapAttachmentStore.resolve(
            relativePath: "../../outside.png",
            documentURL: document,
            repositoryURL: root
        ))
        XCTAssertNil(MindMapAttachmentStore.resolve(
            relativePath: "../../attachments/../secret.png",
            documentURL: document,
            repositoryURL: root
        ))
    }
}
