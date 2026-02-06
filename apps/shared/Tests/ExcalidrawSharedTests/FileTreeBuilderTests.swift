import XCTest
@testable import ExcalidrawShared

final class FileTreeBuilderTests: XCTestCase {
    
    func testBuildTreeWithFlatFiles() {
        let folderId = UUID()
        let entries = [
            ExcalidrawFileEntry(
                folderId: folderId,
                relativePath: "file1.excalidraw",
                fileName: "file1.excalidraw",
                fileURL: URL(fileURLWithPath: "/test/file1.excalidraw"),
                modifiedAt: Date(),
                fileSize: 100
            ),
            ExcalidrawFileEntry(
                folderId: folderId,
                relativePath: "file2.excalidraw",
                fileName: "file2.excalidraw",
                fileURL: URL(fileURLWithPath: "/test/file2.excalidraw"),
                modifiedAt: Date(),
                fileSize: 200
            )
        ]
        
        let root = FileTreeBuilder.buildTree(entries: entries, folderName: "TestFolder")
        
        XCTAssertEqual(root.name, "TestFolder")
        XCTAssertTrue(root.isFolder)
        XCTAssertTrue(root.isExpanded)
        XCTAssertEqual(root.children.count, 2)
        
        // 验证子节点是文件
        for child in root.children {
            XCTAssertFalse(child.isFolder)
            XCTAssertNotNil(child.fileEntry)
        }
    }
    
    func testBuildTreeWithNestedFolders() {
        let folderId = UUID()
        let entries = [
            ExcalidrawFileEntry(
                folderId: folderId,
                relativePath: "folder1/file1.excalidraw",
                fileName: "file1.excalidraw",
                fileURL: URL(fileURLWithPath: "/test/folder1/file1.excalidraw"),
                modifiedAt: Date(),
                fileSize: 100
            ),
            ExcalidrawFileEntry(
                folderId: folderId,
                relativePath: "folder1/subfolder/file2.excalidraw",
                fileName: "file2.excalidraw",
                fileURL: URL(fileURLWithPath: "/test/folder1/subfolder/file2.excalidraw"),
                modifiedAt: Date(),
                fileSize: 200
            ),
            ExcalidrawFileEntry(
                folderId: folderId,
                relativePath: "folder2/file3.excalidraw",
                fileName: "file3.excalidraw",
                fileURL: URL(fileURLWithPath: "/test/folder2/file3.excalidraw"),
                modifiedAt: Date(),
                fileSize: 300
            )
        ]
        
        let root = FileTreeBuilder.buildTree(entries: entries, folderName: "TestFolder")
        
        XCTAssertEqual(root.children.count, 2) // folder1, folder2
        
        // 找到 folder1
        let folder1 = root.children.first { $0.name == "folder1" }
        XCTAssertNotNil(folder1)
        XCTAssertTrue(folder1!.isFolder)
        XCTAssertEqual(folder1!.children.count, 2) // file1.excalidraw, subfolder
        
        // 找到 subfolder
        let subfolder = folder1!.children.first { $0.name == "subfolder" }
        XCTAssertNotNil(subfolder)
        XCTAssertTrue(subfolder!.isFolder)
        XCTAssertEqual(subfolder!.children.count, 1) // file2.excalidraw
    }
    
    func testBuildTreeWithMixedContent() {
        let folderId = UUID()
        let entries = [
            ExcalidrawFileEntry(
                folderId: folderId,
                relativePath: "rootFile.excalidraw",
                fileName: "rootFile.excalidraw",
                fileURL: URL(fileURLWithPath: "/test/rootFile.excalidraw"),
                modifiedAt: Date(),
                fileSize: 100
            ),
            ExcalidrawFileEntry(
                folderId: folderId,
                relativePath: "subFolder/nestedFile.excalidraw",
                fileName: "nestedFile.excalidraw",
                fileURL: URL(fileURLWithPath: "/test/subFolder/nestedFile.excalidraw"),
                modifiedAt: Date(),
                fileSize: 200
            )
        ]
        
        let root = FileTreeBuilder.buildTree(entries: entries, folderName: "TestFolder")
        
        XCTAssertEqual(root.children.count, 2)
        
        // 根级别应该有一个文件和一个文件夹
        let rootFile = root.children.first { $0.name == "rootFile.excalidraw" }
        let subFolder = root.children.first { $0.name == "subFolder" }
        
        XCTAssertNotNil(rootFile)
        XCTAssertFalse(rootFile!.isFolder)
        
        XCTAssertNotNil(subFolder)
        XCTAssertTrue(subFolder!.isFolder)
        XCTAssertEqual(subFolder!.children.count, 1)
    }
    
    func testBuildTreeWithEmptyEntries() {
        let root = FileTreeBuilder.buildTree(entries: [], folderName: "EmptyFolder")
        
        XCTAssertEqual(root.name, "EmptyFolder")
        XCTAssertTrue(root.isFolder)
        XCTAssertEqual(root.children.count, 0)
    }
    
    func testBuildTreeSortsFilesAlphabetically() {
        let folderId = UUID()
        let entries = [
            ExcalidrawFileEntry(
                folderId: folderId,
                relativePath: "zebra.excalidraw",
                fileName: "zebra.excalidraw",
                fileURL: URL(fileURLWithPath: "/test/zebra.excalidraw"),
                modifiedAt: Date(),
                fileSize: 100
            ),
            ExcalidrawFileEntry(
                folderId: folderId,
                relativePath: "apple.excalidraw",
                fileName: "apple.excalidraw",
                fileURL: URL(fileURLWithPath: "/test/apple.excalidraw"),
                modifiedAt: Date(),
                fileSize: 200
            ),
            ExcalidrawFileEntry(
                folderId: folderId,
                relativePath: "mango.excalidraw",
                fileName: "mango.excalidraw",
                fileURL: URL(fileURLWithPath: "/test/mango.excalidraw"),
                modifiedAt: Date(),
                fileSize: 300
            )
        ]
        
        let root = FileTreeBuilder.buildTree(entries: entries, folderName: "TestFolder")
        
        XCTAssertEqual(root.children.count, 3)
        XCTAssertEqual(root.children[0].name, "apple.excalidraw")
        XCTAssertEqual(root.children[1].name, "mango.excalidraw")
        XCTAssertEqual(root.children[2].name, "zebra.excalidraw")
    }
}
