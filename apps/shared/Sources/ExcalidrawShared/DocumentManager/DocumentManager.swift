import Combine
import Foundation

public struct DocumentScene {
    public let docId: String
    public let sceneJson: Any
    public let readOnly: Bool

    public init(docId: String, sceneJson: Any, readOnly: Bool) {
        self.docId = docId
        self.sceneJson = sceneJson
        self.readOnly = readOnly
    }
}

public enum DocumentIndexStatus: String {
    case idle
    case refreshing

    public var description: String {
        rawValue.capitalized
    }
}

public final class DocumentManager: ObservableObject {
    @Published public private(set) var sources: [FolderSource] = []
    @Published public private(set) var indexedEntries: [ExcalidrawFileEntry] = []
    @Published public private(set) var indexStatus: DocumentIndexStatus = .idle
    @Published public private(set) var currentEntry: ExcalidrawFileEntry?
    @Published public var activeFolderId: UUID?

    private let store: FolderSourceStore
    private let saveQueue: DispatchQueue
    private var cancellables: Set<AnyCancellable> = []

    public init(store: FolderSourceStore = FolderSourceStore()) {
        self.store = store
        self.saveQueue = DispatchQueue(label: "com.xexcalidraw.document-manager.save", qos: .utility)

        store.$sources
            .receive(on: DispatchQueue.main)
            .assign(to: &$sources)

        store.$indexedEntries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in
                self?.indexedEntries = entries
                self?.indexStatus = .idle
            }
            .store(in: &cancellables)
    }

    public var folderStore: FolderSourceStore {
        store
    }

    public func addFolder(url: URL) throws {
        try store.addFolder(url: url)
    }

    public func removeFolder(id: UUID) {
        store.removeFolder(id: id)
    }

    public func refreshIndexes() {
        indexStatus = .refreshing
        store.refreshAllIndexes()
    }

    public func open(entry: ExcalidrawFileEntry) throws -> DocumentScene {
        let data = try Data(contentsOf: entry.fileURL)
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let now = Date()
        let updatedEntry = store.updateLastOpenedAt(for: entry.fileURL, date: now) ?? entry
        currentEntry = updatedEntry
        activeFolderId = updatedEntry.folderId
        return DocumentScene(docId: updatedEntry.fileURL.path, sceneJson: jsonObject, readOnly: false)
    }

    public func mostRecentEntry() -> ExcalidrawFileEntry? {
        indexedEntries.max {
            let lhsDate = $0.lastOpenedAt ?? $0.modifiedAt
            let rhsDate = $1.lastOpenedAt ?? $1.modifiedAt
            return lhsDate < rhsDate
        }
    }

    public func saveScene(
        docId: String,
        sceneJson: Any,
        completion: @escaping (Result<ExcalidrawFileEntry, Error>) -> Void
    ) {
        saveQueue.async { [weak self] in
            guard let self else { return }
            do {
                let targetURL = try self.resolveSaveURL(docId: docId)
                let jsonData = try JSONSerialization.data(withJSONObject: sceneJson, options: [.prettyPrinted])
                try jsonData.write(to: targetURL, options: [.atomic])
                DispatchQueue.main.async {
                    let entry = self.updateIndexAfterSave(fileURL: targetURL)
                    if let entry {
                        completion(.success(entry))
                    } else {
                        completion(.failure(DocumentManagerError.unindexedFile))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private func resolveSaveURL(docId: String) throws -> URL {
        if let currentEntry, docId == currentEntry.fileURL.path {
            return currentEntry.fileURL
        }

        let potentialURL = URL(fileURLWithPath: docId)
        if FileManager.default.fileExists(atPath: potentialURL.path) {
            return potentialURL
        }

        guard let folderURL = defaultFolderURL() else {
            throw DocumentManagerError.missingFolder
        }

        let fileName = docId.hasSuffix(".excalidraw") ? docId : "\(docId).excalidraw"
        return folderURL.appendingPathComponent(fileName)
    }

    private func defaultFolderURL() -> URL? {
        if let activeFolderId,
           let source = sources.first(where: { $0.id == activeFolderId }),
           let url = store.resolveURL(for: source) {
            return url
        }

        guard let source = sources.first else {
            return nil
        }
        return store.resolveURL(for: source)
    }

    private func updateIndexAfterSave(fileURL: URL) -> ExcalidrawFileEntry? {
        if let updated = store.updateEntryAfterSave(for: fileURL) {
            currentEntry = updated
            return updated
        }

        guard let (source, rootURL) = matchingSource(for: fileURL) else {
            return nil
        }

        let entry = store.upsertEntry(for: fileURL, folderId: source.id, rootURL: rootURL, lastOpenedAt: Date())
        currentEntry = entry
        activeFolderId = source.id
        return entry
    }

    private func matchingSource(for fileURL: URL) -> (FolderSource, URL)? {
        for source in sources {
            guard let rootURL = store.resolveURL(for: source) else { continue }
            let rootPath = rootURL.standardizedFileURL.path
            let filePath = fileURL.standardizedFileURL.path
            if filePath.hasPrefix(rootPath) {
                return (source, rootURL)
            }
        }
        return nil
    }
}

public enum DocumentManagerError: LocalizedError {
    case missingFolder
    case unindexedFile

    public var errorDescription: String? {
        switch self {
        case .missingFolder:
            return "No folder selected for saving documents."
        case .unindexedFile:
            return "Unable to update index for saved document."
        }
    }
}
