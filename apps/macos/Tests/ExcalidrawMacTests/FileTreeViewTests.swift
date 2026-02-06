import XCTest
@testable import ExcalidrawMac
@testable import ExcalidrawShared

final class FileTreeViewTests: XCTestCase {
    func testBuildTreeIncludesEmptyFolderPaths() {
        let sourceId = UUID()
        let folderId = UUID()
        let entries = [
            ExcalidrawFileEntry(
                folderId: folderId,
                relativePath: "root.excalidraw",
                fileName: "root.excalidraw",
                fileURL: URL(fileURLWithPath: "/tmp/root.excalidraw"),
                modifiedAt: Date(),
                fileSize: 10
            )
        ]

        let root = FileTreeBuilder.buildTree(
            entries: entries,
            folderName: "Workspace",
            sourceId: sourceId,
            folderPaths: ["EmptyFolder", "A/B/C"]
        )

        let emptyFolder = root.children.first { $0.name == "EmptyFolder" }
        XCTAssertNotNil(emptyFolder)
        XCTAssertTrue(emptyFolder?.isFolder == true)

        let aFolder = root.children.first { $0.name == "A" }
        XCTAssertNotNil(aFolder)
        XCTAssertEqual(aFolder?.sourceId, sourceId)

        let bFolder = aFolder?.children.first { $0.name == "B" }
        let cFolder = bFolder?.children.first { $0.name == "C" }
        XCTAssertNotNil(cFolder)
        XCTAssertEqual(cFolder?.sourceId, sourceId)
    }

    func testBuildTreePropagatesSourceIdToFilesAndFolders() {
        let sourceId = UUID()
        let folderId = UUID()
        let entry = ExcalidrawFileEntry(
            folderId: folderId,
            relativePath: "nested/file.excalidraw",
            fileName: "file.excalidraw",
            fileURL: URL(fileURLWithPath: "/tmp/nested/file.excalidraw"),
            modifiedAt: Date(),
            fileSize: 100
        )

        let root = FileTreeBuilder.buildTree(
            entries: [entry],
            folderName: "Workspace",
            sourceId: sourceId
        )

        let nestedFolder = root.children.first { $0.name == "nested" }
        XCTAssertNotNil(nestedFolder)
        XCTAssertEqual(nestedFolder?.sourceId, sourceId)

        let fileNode = nestedFolder?.children.first { !$0.isFolder }
        XCTAssertNotNil(fileNode)
        XCTAssertEqual(fileNode?.sourceId, sourceId)
        XCTAssertEqual(fileNode?.fileEntry?.fileName, "file.excalidraw")
    }

    func testBuildTreeSortsFilesByLocalizedName() {
        let folderId = UUID()
        let entries = [
            ExcalidrawFileEntry(
                folderId: folderId,
                relativePath: "b.excalidraw",
                fileName: "b.excalidraw",
                fileURL: URL(fileURLWithPath: "/tmp/b.excalidraw"),
                modifiedAt: Date(),
                fileSize: 20
            ),
            ExcalidrawFileEntry(
                folderId: folderId,
                relativePath: "a.excalidraw",
                fileName: "a.excalidraw",
                fileURL: URL(fileURLWithPath: "/tmp/a.excalidraw"),
                modifiedAt: Date(),
                fileSize: 20
            )
        ]

        let root = FileTreeBuilder.buildTree(entries: entries, folderName: "Workspace")
        XCTAssertEqual(root.children.map(\.name), ["a.excalidraw", "b.excalidraw"])
    }
}
