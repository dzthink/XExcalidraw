import Foundation

public class FileTreeNode: Identifiable, ObservableObject {
    public let id = UUID()
    public let name: String
    public let path: String
    public let isFolder: Bool
    public let fileEntry: ExcalidrawFileEntry?
    public let sourceId: UUID?  // 根目录对应的 FolderSource id
    @Published public var isExpanded: Bool
    @Published public var children: [FileTreeNode]
    public weak var parent: FileTreeNode?
    
    public var isRoot: Bool {
        parent == nil
    }
    
    public var root: FileTreeNode {
        var current: FileTreeNode = self
        while let p = current.parent {
            current = p
        }
        return current
    }
    
    public init(name: String, path: String, isFolder: Bool, fileEntry: ExcalidrawFileEntry? = nil, sourceId: UUID? = nil, isExpanded: Bool = false, children: [FileTreeNode] = [], parent: FileTreeNode? = nil) {
        self.name = name
        self.path = path
        self.isFolder = isFolder
        self.fileEntry = fileEntry
        self.sourceId = sourceId
        self.isExpanded = isExpanded
        self.children = children
        self.parent = parent
    }
}

public class FileTreeBuilder {
    public static func buildTree(
        entries: [ExcalidrawFileEntry],
        folderName: String,
        sourceId: UUID? = nil,
        folderPaths: [String] = []
    ) -> FileTreeNode {
        let root = FileTreeNode(name: folderName, path: "", isFolder: true, sourceId: sourceId, isExpanded: true)
        
        // Group entries by their directory path
        var pathGroups: [String: [ExcalidrawFileEntry]] = [:]
        
        for entry in entries {
            let dirPath = (entry.relativePath as NSString).deletingLastPathComponent
            let normalizedPath = dirPath == "." ? "" : dirPath
            pathGroups[normalizedPath, default: []].append(entry)
        }
        
        // Include explicit folder paths so empty folders are also visible in the tree.
        for folderPath in folderPaths {
            pathGroups[folderPath, default: []] = pathGroups[folderPath, default: []]
        }

        // Sort paths to ensure parent folders are created before children
        let sortedPaths = pathGroups.keys.sorted { $0 < $1 }
        
        // Create folder structure
        var folderMap: [String: FileTreeNode] = ["": root]
        
        for path in sortedPaths {
            // Ensure all parent folders exist
            var currentPath = ""
            let components = path.split(separator: "/").map(String.init)
            
            for component in components {
                let parentPath = currentPath
                currentPath = currentPath.isEmpty ? component : "\(currentPath)/\(component)"
                
                if folderMap[currentPath] == nil {
                    let parentNode = folderMap[parentPath]
                    let newFolder = FileTreeNode(
                        name: component,
                        path: currentPath,
                        isFolder: true,
                        sourceId: sourceId,
                        isExpanded: false,
                        parent: parentNode
                    )
                    folderMap[currentPath] = newFolder
                    
                    // Add to parent
                    if let parent = parentNode {
                        parent.children.append(newFolder)
                    }
                }
            }
            
            // Add files to the folder
            if let folder = folderMap[path] {
                let files = pathGroups[path, default: []]
                    .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
                for file in files {
                    let fileNode = FileTreeNode(
                        name: file.fileName,
                        path: file.relativePath,
                        isFolder: false,
                        fileEntry: file,
                        sourceId: sourceId,
                        isExpanded: false,
                        parent: folder
                    )
                    folder.children.append(fileNode)
                }
            }
        }
        
        return root
    }
}
