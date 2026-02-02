import Foundation

public struct FolderSource: Identifiable, Codable, Equatable {
    public let id: UUID
    public let bookmarkData: Data
    public let displayName: String
    public let recursive: Bool
    public let addedAt: Date

    public init(
        id: UUID = UUID(),
        bookmarkData: Data,
        displayName: String,
        recursive: Bool,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.bookmarkData = bookmarkData
        self.displayName = displayName
        self.recursive = recursive
        self.addedAt = addedAt
    }
}
