import Foundation

public enum MindMapAttachmentError: LocalizedError {
    case invalidDocument
    case unsupportedImage
    case invalidPath

    public var errorDescription: String? {
        switch self {
        case .invalidDocument: return "Open a mind map in a repository first"
        case .unsupportedImage: return "Unsupported image format"
        case .invalidPath: return "Invalid attachment path"
        }
    }
}

public enum MindMapAttachmentStore {
    public static var directoryName: String { EditorPreferences.attachmentDirectory() }

    public static func save(
        imageData: Data,
        mimeType: String,
        documentURL: URL,
        repositoryURL: URL,
        directoryName: String = EditorPreferences.attachmentDirectory()
    ) throws -> String {
        let fileExtension: String
        switch mimeType.lowercased() {
        case "image/png": fileExtension = "png"
        case "image/jpeg", "image/jpg": fileExtension = "jpg"
        case "image/gif": fileExtension = "gif"
        case "image/webp": fileExtension = "webp"
        default: throw MindMapAttachmentError.unsupportedImage
        }
        guard !imageData.isEmpty,
              documentURL.pathExtension.lowercased() == "mindmap",
              let depth = depthWithinRepository(documentURL: documentURL, repositoryURL: repositoryURL) else {
            throw MindMapAttachmentError.invalidDocument
        }

        guard EditorPreferences.normalizedDirectory(directoryName) == directoryName else { throw MindMapAttachmentError.invalidPath }
        let directory = repositoryURL.appendingPathComponent(directoryName, isDirectory: true)
        let resolvedRoot = repositoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        guard resolvedDirectory.path.hasPrefix(resolvedRoot.path + "/") else {
            throw MindMapAttachmentError.invalidPath
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString.lowercased()).\(fileExtension)"
        try imageData.write(to: directory.appendingPathComponent(fileName), options: [.atomic])
        return String(repeating: "../", count: depth) + "\(directoryName)/\(fileName)"
    }

    public static func resolve(
        relativePath: String,
        documentURL: URL,
        repositoryURL: URL,
        allowedDirectories: [String] = EditorPreferences.attachmentDirectories()
    ) -> URL? {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("://"),
              !relativePath.contains("\\"),
              depthWithinRepository(documentURL: documentURL, repositoryURL: repositoryURL) != nil else {
            return nil
        }
        let target = documentURL.deletingLastPathComponent()
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let root = repositoryURL.standardizedFileURL.resolvingSymlinksInPath()
        guard target.path.hasPrefix(root.path + "/"),
              allowedDirectories.compactMap(EditorPreferences.normalizedDirectory).contains(where: { name in
                  let directory = repositoryURL.appendingPathComponent(name, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
                  return directory.path.hasPrefix(root.path + "/") && target.deletingLastPathComponent().path == directory.path
              }),
              ["png", "jpg", "jpeg", "gif", "webp"].contains(target.pathExtension.lowercased()) else { return nil }
        return target
    }

    private static func depthWithinRepository(documentURL: URL, repositoryURL: URL) -> Int? {
        let root = repositoryURL.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let parent = documentURL.deletingLastPathComponent()
            .standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard parent.count >= root.count, Array(parent.prefix(root.count)) == root else { return nil }
        return parent.count - root.count
    }
}
