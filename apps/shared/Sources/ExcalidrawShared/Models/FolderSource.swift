import Foundation

public struct FolderSource: Identifiable, Codable, Hashable {
    public let id: UUID
    public var displayName: String
    public var bookmarkData: Data

    public init(id: UUID = UUID(), displayName: String, bookmarkData: Data) {
        self.id = id
        self.displayName = displayName
        self.bookmarkData = bookmarkData
    }
}
