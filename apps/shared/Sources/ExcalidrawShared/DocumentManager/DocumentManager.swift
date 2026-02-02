import Combine
import CryptoKit
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

public struct DocumentDraft {
    public let docId: String
    public let sceneJson: Any
    public let savedAt: Date
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
    @Published public private(set) var pendingDraft: DocumentDraft?

    private let store: FolderSourceStore
    private let saveQueue: DispatchQueue
    private var cancellables: Set<AnyCancellable> = []
    private let draftDirectory: URL

    public init(store: FolderSourceStore = FolderSourceStore()) {
        self.store = store
        self.saveQueue = DispatchQueue(label: "com.xexcalidraw.document-manager.save", qos: .utility)
        self.draftDirectory = DocumentManager.makeDraftDirectory()

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

        loadPendingDraft()
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
                self.writeDraft(docId: docId, sceneJson: sceneJson)
                let targetURL = try self.resolveSaveURL(docId: docId)
                let jsonData = try JSONSerialization.data(withJSONObject: sceneJson, options: [.prettyPrinted])
                try jsonData.write(to: targetURL, options: [.atomic])
                DispatchQueue.main.async {
                    self.clearDraft(docId: docId)
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

    public func discardPendingDraft() {
        guard let pendingDraft else { return }
        removeDraftFile(for: pendingDraft.docId)
        DispatchQueue.main.async {
            self.pendingDraft = nil
        }
    }

    public func consumePendingDraft() -> DocumentDraft? {
        guard let pendingDraft else { return nil }
        removeDraftFile(for: pendingDraft.docId)
        DispatchQueue.main.async {
            self.pendingDraft = nil
        }
        return pendingDraft
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

    private func loadPendingDraft() {
        saveQueue.async { [weak self] in
            guard let self else { return }
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: self.draftDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let candidates = urls.filter { $0.pathExtension == "json" }
            let sorted = candidates.sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
            for url in sorted {
                if let draft = self.readDraft(from: url) {
                    DispatchQueue.main.async {
                        self.pendingDraft = draft
                    }
                    return
                }
            }
        }
    }

    private func writeDraft(docId: String, sceneJson: Any) {
        let payload: [String: Any] = [
            "docId": docId,
            "savedAt": ISO8601DateFormatter().string(from: Date()),
            "sceneJson": sceneJson
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else {
            return
        }
        let fileURL = draftFileURL(for: docId)
        do {
            try FileManager.default.createDirectory(at: draftDirectory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic])
            if let draft = readDraft(from: fileURL) {
                DispatchQueue.main.async {
                    self.pendingDraft = draft
                }
            }
        } catch {
            return
        }
    }

    private func clearDraft(docId: String) {
        removeDraftFile(for: docId)
        DispatchQueue.main.async {
            if self.pendingDraft?.docId == docId {
                self.pendingDraft = nil
            }
        }
    }

    private func removeDraftFile(for docId: String) {
        let fileURL = draftFileURL(for: docId)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func readDraft(from url: URL) -> DocumentDraft? {
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let docId = json["docId"] as? String,
            let sceneJson = json["sceneJson"]
        else {
            return nil
        }
        let savedAtString = json["savedAt"] as? String ?? ""
        let savedAt = ISO8601DateFormatter().date(from: savedAtString) ?? Date()
        return DocumentDraft(docId: docId, sceneJson: sceneJson, savedAt: savedAt)
    }

    private func draftFileURL(for docId: String) -> URL {
        let hashed = Self.hashDocId(docId)
        return draftDirectory.appendingPathComponent("\(hashed).json")
    }

    private static func hashDocId(_ docId: String) -> String {
        let digest = SHA256.hash(data: Data(docId.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func makeDraftDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ExcalidrawDrafts", isDirectory: true)
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
