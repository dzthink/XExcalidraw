import Foundation

public class FileTreeNode: Identifiable, ObservableObject {
    public let id = UUID()
    public let name: String
    public let path: String
    public let isFolder: Bool
    public let fileEntry: ExcalidrawFileEntry?
    @Published public var isExpanded: Bool
    @Published public var children: [FileTreeNode]
    
    public init(name: String, path: String, isFolder: Bool, fileEntry: ExcalidrawFileEntry? = nil, isExpanded: Bool = false, children: [FileTreeNode] = []) {
        self.name = name
        self.path = path
        self.isFolder = isFolder
        self.fileEntry = fileEntry
        self.isExpanded = isExpanded
        self.children = children
    }
}

public class FileTreeBuilder {
    public static func buildTree(entries: [ExcalidrawFileEntry], folderName: String) -> FileTreeNode {
        let root = FileTreeNode(name: folderName, path: "", isFolder: true, isExpanded: true)
        
        // Group entries by their directory path
        var pathGroups: [String: [ExcalidrawFileEntry]] = [:]
        
        for entry in entries {
            let dirPath = (entry.relativePath as NSString).deletingLastPathComponent
            let normalizedPath = dirPath == "." ? "" : dirPath
            pathGroups[normalizedPath, default: []].append(entry)
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
                    let newFolder = FileTreeNode(
                        name: component,
                        path: currentPath,
                        isFolder: true,
                        isExpanded: false
                    )
                    folderMap[currentPath] = newFolder
                    
                    // Add to parent
                    if let parent = folderMap[parentPath] {
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
                        isExpanded: false
                    )
                    folder.children.append(fileNode)
                }
            }
        }
        
        return root
    }
}
