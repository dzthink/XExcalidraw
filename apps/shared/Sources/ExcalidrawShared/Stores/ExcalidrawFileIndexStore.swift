import Foundation

public protocol ExcalidrawFileIndexStore {
    func loadEntries() throws -> [ExcalidrawFileEntry]
    func saveEntries(_ entries: [ExcalidrawFileEntry]) throws
}

public final class ExcalidrawJSONFileIndexStore: ExcalidrawFileIndexStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL = ExcalidrawJSONFileIndexStore.defaultURL()) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func loadEntries() throws -> [ExcalidrawFileEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([ExcalidrawFileEntry].self, from: data)
    }

    public func saveEntries(_ entries: [ExcalidrawFileEntry]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: [.atomic])
    }

    public static func defaultURL(
        baseDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ) -> URL {
        baseDirectory
            .appendingPathComponent("XExcalidraw", isDirectory: true)
            .appendingPathComponent("excalidraw-file-index.json")
    }
}
