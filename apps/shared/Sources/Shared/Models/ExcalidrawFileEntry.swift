import Foundation

public struct ExcalidrawFileEntry: Codable, Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let directoryPath: String
    public let filePath: String
    public let modifiedAt: Date

    public init(id: UUID = UUID(), name: String, directoryPath: String, filePath: String, modifiedAt: Date) {
        self.id = id
        self.name = name
        self.directoryPath = directoryPath
        self.filePath = filePath
        self.modifiedAt = modifiedAt
    }
}
