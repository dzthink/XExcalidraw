import Foundation

public struct LoadScenePayload: Codable, Equatable {
    public let docId: UUID
    public let sceneJson: Data
    public let readOnly: Bool

    public init(docId: UUID, sceneJson: Data, readOnly: Bool) {
        self.docId = docId
        self.sceneJson = sceneJson
        self.readOnly = readOnly
    }
}

public struct SetAppStatePayload: Codable, Equatable {
    public let theme: String

    public init(theme: String) {
        self.theme = theme
    }
}

public struct RequestExportPayload: Codable, Equatable {
    public let format: String
    public let embedScene: Bool

    public init(format: String, embedScene: Bool) {
        self.format = format
        self.embedScene = embedScene
    }
}

public struct DidChangePayload: Codable, Equatable {
    public let docId: UUID
    public let dirty: Bool

    public init(docId: UUID, dirty: Bool) {
        self.docId = docId
        self.dirty = dirty
    }
}

public struct SaveScenePayload: Codable, Equatable {
    public let docId: UUID
    public let sceneJson: Data

    public init(docId: UUID, sceneJson: Data) {
        self.docId = docId
        self.sceneJson = sceneJson
    }
}

public struct ExportResultPayload: Codable, Equatable {
    public let format: String
    public let dataBase64: String

    public init(format: String, dataBase64: String) {
        self.format = format
        self.dataBase64 = dataBase64
    }
}
