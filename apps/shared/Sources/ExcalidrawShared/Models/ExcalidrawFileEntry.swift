import Foundation

public struct ExcalidrawFileEntry: Identifiable, Codable, Equatable {
    public let id: UUID
    public let folderId: UUID
    public let relativePath: String
    public let fileName: String
    public let fileURL: URL
    public let modifiedAt: Date
    public let fileSize: Int64
    public let lastOpenedAt: Date?
    public let thumbnailPath: String?

    public init(
        id: UUID = UUID(),
        folderId: UUID,
        relativePath: String,
        fileName: String,
        fileURL: URL,
        modifiedAt: Date,
        fileSize: Int64,
        lastOpenedAt: Date? = nil,
        thumbnailPath: String? = nil
    ) {
        self.id = id
        self.folderId = folderId
        self.relativePath = relativePath
        self.fileName = fileName
        self.fileURL = fileURL
        self.modifiedAt = modifiedAt
        self.fileSize = fileSize
        self.lastOpenedAt = lastOpenedAt
        self.thumbnailPath = thumbnailPath
    }
}
