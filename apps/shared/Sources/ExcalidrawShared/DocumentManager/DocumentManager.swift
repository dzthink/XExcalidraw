import Combine
import CryptoKit
import Compression
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

public struct DocumentDraft: Equatable {
    public let docId: String
    public let sceneJson: Any
    public let savedAt: Date

    public static func == (lhs: DocumentDraft, rhs: DocumentDraft) -> Bool {
        lhs.docId == rhs.docId && lhs.savedAt == rhs.savedAt
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
    @Published public private(set) var pendingDraft: DocumentDraft?
    
    public var hasActiveSource: Bool {
        store.activeSource != nil
    }
    
    public var activeSource: FolderSource? {
        store.activeSource
    }
    
    public var activeSourceEntries: [ExcalidrawFileEntry] {
        store.activeSourceEntries.sorted {
            ($0.lastOpenedAt ?? $0.modifiedAt) > ($1.lastOpenedAt ?? $1.modifiedAt)
        }
    }

    private let store: FolderSourceStore
    private let saveQueue: DispatchQueue
    // Mutated on saveQueue; UI reads use renameLock.
    private var renamedDocumentURLs: [String: URL] = [:]
    private let renameLock = NSLock()
    private var cancellables: Set<AnyCancellable> = []
    private let draftDirectory: URL

    public init(store: FolderSourceStore = FolderSourceStore(), draftDirectory: URL? = nil) {
        self.store = store
        self.saveQueue = DispatchQueue(label: "com.xexcalidraw.document-manager.save", qos: .utility)
        self.draftDirectory = draftDirectory ?? DocumentManager.makeDraftDirectory()

        store.$sources
            .receive(on: DispatchQueue.main)
            .assign(to: &$sources)
        
        store.$activeSourceId
            .receive(on: DispatchQueue.main)
            .assign(to: &$activeFolderId)

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
    
    public func switchToSource(id: UUID) {
        store.switchToSource(id: id)
        currentEntry = nil
    }
    
    public func getSourceHistory() -> [FolderSource] {
        store.getSourceHistory()
    }

    public func refreshIndexes() {
        guard !sources.isEmpty else { indexStatus = .idle; return }
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
    
    /// Read cloud-backed documents off the UI thread; callers activate only the accepted result.
    public func read(entry: ExcalidrawFileEntry, completion: @escaping (Result<DocumentScene, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result<DocumentScene, Error> {
                let data = try Data(contentsOf: entry.fileURL)
                let json = try JSONSerialization.jsonObject(with: data)
                return DocumentScene(docId: entry.fileURL.path, sceneJson: json, readOnly: false)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    public func activate(entry: ExcalidrawFileEntry) {
        currentEntry = store.updateLastOpenedAt(for: entry.fileURL, date: Date()) ?? entry
        activeFolderId = entry.folderId
    }

    public func clearCurrentEntry() {
        currentEntry = nil
    }

    public func attachmentContext(docId: String) -> (documentURL: URL, repositoryURL: URL)? {
        guard let entry = currentEntry,
              entry.fileURL.path == docId,
              entry.fileURL.pathExtension.lowercased() == "mindmap",
              let source = sources.first(where: { $0.id == entry.folderId }),
              let rootURL = store.resolveURL(for: source) else {
            return nil
        }
        return (entry.fileURL, rootURL)
    }

    public func importScene(
        from fileURL: URL,
        completion: @escaping (Result<ExcalidrawFileEntry, Error>) -> Void
    ) {
        saveQueue.async { [weak self] in
            guard let self else { return }
            do {
                let sceneJson = try self.loadImportScene(from: fileURL)
                let targetName = self.makeImportDocumentName(from: fileURL) + (fileURL.pathExtension.lowercased() == "mindmap" ? ".mindmap" : "")
                let targetURL = try self.resolveSaveURL(docId: targetName)
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

    public func mostRecentEntry() -> ExcalidrawFileEntry? {
        indexedEntries.max {
            let lhsDate = $0.lastOpenedAt ?? $0.modifiedAt
            let rhsDate = $1.lastOpenedAt ?? $1.modifiedAt
            return lhsDate < rhsDate
        }
    }

    public func saveScene(
        docId: String,
        sceneJson rawScene: Any,
        completion: @escaping (Result<ExcalidrawFileEntry, Error>) -> Void
    ) {
        let submittedEntryID = currentEntry?.id
        let submittedURL = currentEntry?.fileURL
        let fallbackFolderURL = defaultFolderURL()
        saveQueue.async { [weak self] in
            guard let self else { return }
            do {
                let sceneJson: Any
                if let text = rawScene as? String {
                    sceneJson = try JSONSerialization.jsonObject(with: Data(text.utf8))
                } else {
                    sceneJson = rawScene
                }
                guard JSONSerialization.isValidJSONObject(sceneJson) else { throw DocumentManagerError.invalidImportData }
                self.writeDraft(docId: docId, sceneJson: sceneJson)
                let targetURL = try self.resolveSaveURL(docId: docId, currentURL: submittedURL, fallbackFolderURL: fallbackFolderURL)
                let jsonData = try JSONSerialization.data(withJSONObject: sceneJson, options: [.prettyPrinted])
                try jsonData.write(to: targetURL, options: [.atomic])
                self.removeDraftFile(for: docId)
                let values = try? targetURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                DispatchQueue.main.async {
                    if self.pendingDraft?.docId == docId { self.pendingDraft = nil }
                    let entry = self.updateIndexAfterSave(fileURL: targetURL, modifiedAt: values?.contentModificationDate, fileSize: values?.fileSize, activate: self.currentEntry?.id == submittedEntryID)
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

    public func createBlankDocument(
        in folderId: UUID? = nil,
        relativeFolderPath: String = "",
        type: SiyeDocumentType = .excalidraw,
        completion: @escaping (Result<DocumentScene, Error>) -> Void
    ) {
        let target: (FolderSource, URL)? = {
            if let folderId, let source = sources.first(where: { $0.id == folderId }), let url = store.resolveURL(for: source) {
                return (source, url)
            }
            return defaultFolderSource()
        }()
        guard let (targetSource, targetFolderURL) = target else { completion(.failure(DocumentManagerError.missingFolder)); return }
        saveQueue.async { [weak self] in
            guard let self else { return }
            let destinationURL = relativeFolderPath.isEmpty
                ? targetFolderURL
                : targetFolderURL.appendingPathComponent(relativeFolderPath, isDirectory: true)
            let fileURL = self.makeUntitledFileURL(in: destinationURL, type: type)
            let sceneJson = type.blankScene
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: sceneJson, options: [.prettyPrinted])
                try jsonData.write(to: fileURL, options: [.atomic])
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
                DispatchQueue.main.async {
                    guard let entry = self.store.upsertEntry(for: fileURL, folderId: targetSource.id, rootURL: targetFolderURL, lastOpenedAt: Date(), resourceValues: values) else {
                        completion(.failure(DocumentManagerError.unindexedFile))
                        return
                    }
                    self.currentEntry = entry
                    self.activeFolderId = targetSource.id
                    completion(.success(DocumentScene(
                        docId: entry.fileURL.path,
                        sceneJson: sceneJson,
                        readOnly: false
                    )))
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

    public func renameCurrentEntry(to newName: String) throws {
        guard let entry = currentEntry else {
            throw DocumentManagerError.noCurrentEntry
        }
        try renameEntry(entry, to: newName)
    }

    public func renameEntry(_ entry: ExcalidrawFileEntry, to newName: String) throws {
        let newURL = try saveQueue.sync { try moveEntry(entry, to: newName) }
        finishRename(entry, newURL: newURL)
    }

    public func renameEntry(_ entry: ExcalidrawFileEntry, to newName: String, completion: @escaping (Result<ExcalidrawFileEntry, Error>) -> Void) {
        saveQueue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.moveEntry(entry, to: newName) }
            DispatchQueue.main.async {
                switch result {
                case .success(let newURL):
                    self.finishRename(entry, newURL: newURL)
                    completion(.success(self.store.indexedEntries.first(where: { $0.id == entry.id }) ?? entry))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    private func moveEntry(_ entry: ExcalidrawFileEntry, to newName: String) throws -> URL {
        let suffix = entry.fileName.lowercased().hasSuffix(".excalidraw.json") ? ".excalidraw.json" : (SiyeDocumentType(fileName: entry.fileName)?.fileExtension ?? ".excalidraw")
        let sanitizedName = "\(SiyeDocumentType.displayName(from: newName))\(suffix)"
        let oldURL = renamedURL(for: entry.fileURL.path) ?? entry.fileURL
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(sanitizedName)
        guard newURL != oldURL else { return newURL }
        if FileManager.default.fileExists(atPath: newURL.path) { throw DocumentManagerError.fileAlreadyExists }
        try FileManager.default.moveItem(at: oldURL, to: newURL)
        renameLock.lock()
        defer { renameLock.unlock() }
        for oldPath in Array(renamedDocumentURLs.keys) where renamedDocumentURLs[oldPath] == oldURL {
            renamedDocumentURLs[oldPath] = newURL
        }
        renamedDocumentURLs[oldURL.path] = newURL
        return newURL
    }

    private func finishRename(_ entry: ExcalidrawFileEntry, newURL: URL) {
        // Another queued rename may already have moved the same file again.
        let latestURL = renamedURL(for: newURL.path) ?? newURL
        store.updateEntryAfterRename(id: entry.id, newFileURL: latestURL, newFileName: latestURL.lastPathComponent)
        if currentEntry?.id == entry.id,
           let updated = store.indexedEntries.first(where: { $0.id == entry.id }) {
            currentEntry = updated
        }
    }

    private func resolveSaveURL(docId: String) throws -> URL {
        try resolveSaveURL(docId: docId, currentURL: currentEntry?.fileURL, fallbackFolderURL: defaultFolderURL())
    }

    private func resolveSaveURL(docId: String, currentURL: URL?, fallbackFolderURL: URL?) throws -> URL {
        if let renamedURL = renamedURL(for: docId) { return renamedURL }
        if let currentURL, docId == currentURL.path { return currentURL }
        let potentialURL = URL(fileURLWithPath: docId)
        if FileManager.default.fileExists(atPath: potentialURL.path) { return potentialURL }
        guard let folderURL = fallbackFolderURL else { throw DocumentManagerError.missingFolder }
        let fileName = SiyeDocumentType(fileName: docId) != nil ? docId : "\(docId).excalidraw"
        return folderURL.appendingPathComponent(fileName)
    }

    private func defaultFolderURL() -> URL? {
        defaultFolderSource()?.1
    }

    private func defaultFolderSource() -> (FolderSource, URL)? {
        if let activeFolderId,
           let source = sources.first(where: { $0.id == activeFolderId }),
           let url = store.resolveURL(for: source) {
            return (source, url)
        }
        guard let source = sources.first,
              let url = store.resolveURL(for: source) else {
            return nil
        }
        return (source, url)
    }

    private func renamedURL(for path: String) -> URL? {
        renameLock.lock()
        defer { renameLock.unlock() }
        return renamedDocumentURLs[path]
    }

    private func updateIndexAfterSave(fileURL: URL, modifiedAt: Date? = nil, fileSize: Int? = nil, activate: Bool = true) -> ExcalidrawFileEntry? {
        let fileURL = renamedURL(for: fileURL.path) ?? fileURL
        if let updated = store.updateEntryAfterSave(for: fileURL, modifiedAt: modifiedAt, fileSize: fileSize) {
            if activate { currentEntry = updated }
            return updated
        }

        guard let (source, rootURL) = matchingSource(for: fileURL) else {
            return nil
        }

        let entry = store.upsertEntry(for: fileURL, folderId: source.id, rootURL: rootURL, lastOpenedAt: Date())
        if activate { currentEntry = entry; activeFolderId = source.id }
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
            // Don't update pendingDraft here - only load it at app launch
            // This prevents the alert from showing during normal save operations
        } catch {
            return
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

    private func loadImportScene(from fileURL: URL) throws -> Any {
        let fileName = fileURL.lastPathComponent.lowercased()
        let fileExtension = fileURL.pathExtension.lowercased()
        let data = try Data(contentsOf: fileURL)
        if fileExtension == "excalidraw" || fileExtension == "mindmap" {
            return try JSONSerialization.jsonObject(with: data)
        }
        if fileName.hasSuffix(".excalidraw.json") {
            return try JSONSerialization.jsonObject(with: data)
        }
        if fileName.hasSuffix(".excalidraw.svg") {
            return try parseSvgScene(from: data)
        }
        if fileName.hasSuffix(".excalidraw.png") {
            return try parsePngScene(from: data)
        }
        throw DocumentManagerError.unsupportedImportType
    }

    private func makeImportDocumentName(from fileURL: URL) -> String {
        var normalizedURL = fileURL
        normalizedURL.deletePathExtension()
        if normalizedURL.pathExtension.lowercased() == "excalidraw" {
            normalizedURL.deletePathExtension()
        }
        let baseName = normalizedURL.lastPathComponent
        return baseName.isEmpty ? UUID().uuidString : baseName
    }

    private func makeUntitledFileURL(in folderURL: URL, type: SiyeDocumentType) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let baseName = "Untitled-\(timestamp)"
        var candidate = baseName
        var counter = 1
        var fileURL = folderURL.appendingPathComponent("\(candidate)\(type.fileExtension)")
        while FileManager.default.fileExists(atPath: fileURL.path) {
            candidate = "\(baseName)-\(counter)"
            counter += 1
            fileURL = folderURL.appendingPathComponent("\(candidate)\(type.fileExtension)")
        }
        return fileURL
    }

    private func parseSvgScene(from data: Data) throws -> Any {
        guard let svgString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw DocumentManagerError.invalidImportData
        }
        let payloadText = try extractSvgPayload(from: svgString)
        let sceneJson = try decodeEmbeddedScene(from: payloadText)
        guard let sceneData = sceneJson.data(using: .utf8) else {
            throw DocumentManagerError.invalidImportData
        }
        return try JSONSerialization.jsonObject(with: sceneData)
    }

    private func parsePngScene(from data: Data) throws -> Any {
        guard let payloadText = try extractPngPayload(from: data) else {
            throw DocumentManagerError.missingEmbeddedScene
        }
        let sceneJson = try decodeEmbeddedScene(from: payloadText)
        guard let sceneData = sceneJson.data(using: .utf8) else {
            throw DocumentManagerError.invalidImportData
        }
        return try JSONSerialization.jsonObject(with: sceneData)
    }

    private func extractSvgPayload(from svg: String) throws -> String {
        let payloadType = "payload-type:application/vnd.excalidraw+json"
        guard svg.contains(payloadType) else {
            throw DocumentManagerError.missingEmbeddedScene
        }
        let payloadPattern = "<!--\\s*payload-start\\s*-->\\s*(.+?)\\s*<!--\\s*payload-end\\s*-->"
        let payloadRegex = try NSRegularExpression(pattern: payloadPattern, options: [.dotMatchesLineSeparators])
        let payloadRange = NSRange(svg.startIndex..., in: svg)
        guard
            let payloadMatch = payloadRegex.firstMatch(in: svg, options: [], range: payloadRange),
            payloadMatch.numberOfRanges > 1,
            let payloadCapture = Range(payloadMatch.range(at: 1), in: svg)
        else {
            throw DocumentManagerError.invalidImportData
        }
        let versionPattern = "<!--\\s*payload-version:(\\d+)\\s*-->"
        let versionRegex = try NSRegularExpression(pattern: versionPattern, options: [])
        let versionMatch = versionRegex.firstMatch(in: svg, options: [], range: payloadRange)
        var payloadVersion = "1"
        if let versionMatch, versionMatch.numberOfRanges > 1, let versionRange = Range(versionMatch.range(at: 1), in: svg) {
            payloadVersion = String(svg[versionRange])
        }
        let isByteString = payloadVersion != "1"
        let base64Payload = String(svg[payloadCapture]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let payloadData = Data(base64Encoded: base64Payload) else {
            throw DocumentManagerError.invalidImportData
        }
        if isByteString {
            guard let byteString = payloadData.withUnsafeBytes({ buffer in
                String(bytes: buffer.bindMemory(to: UInt8.self), encoding: .isoLatin1)
            }) else {
                throw DocumentManagerError.invalidImportData
            }
            return byteString
        }
        guard let utf8String = String(data: payloadData, encoding: .utf8) else {
            throw DocumentManagerError.invalidImportData
        }
        return utf8String
    }

    private func extractPngPayload(from data: Data) throws -> String? {
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard data.count > signature.count else {
            throw DocumentManagerError.invalidImportData
        }
        if Array(data.prefix(signature.count)) != signature {
            throw DocumentManagerError.invalidImportData
        }
        var index = signature.count
        while index + 8 <= data.count {
            let lengthData = data[index..<(index + 4)]
            let length = lengthData.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let typeStart = index + 4
            let typeEnd = typeStart + 4
            guard typeEnd <= data.count else {
                break
            }
            let typeData = data[typeStart..<typeEnd]
            let typeString = String(bytes: typeData, encoding: .ascii) ?? ""
            let dataStart = typeEnd
            let dataEnd = dataStart + Int(length)
            guard dataEnd <= data.count else {
                break
            }
            if typeString == "tEXt" {
                let chunkData = data[dataStart..<dataEnd]
                if let nullIndex = chunkData.firstIndex(of: 0) {
                    let keywordData = chunkData[..<nullIndex]
                    let textData = chunkData[chunkData.index(after: nullIndex)...]
                    let keyword = String(data: keywordData, encoding: .isoLatin1) ?? ""
                    let text = String(data: textData, encoding: .isoLatin1) ?? ""
                    if keyword == "application/vnd.excalidraw+json" {
                        return text
                    }
                }
            }
            index = dataEnd + 4
        }
        return nil
    }

    private func decodeEmbeddedScene(from payload: String) throws -> String {
        guard let payloadData = payload.data(using: .isoLatin1) else {
            throw DocumentManagerError.invalidImportData
        }
        let jsonObject = try JSONSerialization.jsonObject(with: payloadData)
        guard let dictionary = jsonObject as? [String: Any] else {
            throw DocumentManagerError.invalidImportData
        }
        if let type = dictionary["type"] as? String, type == "excalidraw" {
            return payload
        }
        guard let encodedString = dictionary["encoded"] as? String else {
            throw DocumentManagerError.invalidImportData
        }
        let encoding = dictionary["encoding"] as? String ?? "bstring"
        guard encoding == "bstring" else {
            throw DocumentManagerError.invalidImportData
        }
        let compressed = dictionary["compressed"] as? Bool ?? false
        let encodedBytes = encodedString.unicodeScalars.map { UInt8($0.value) }
        let encodedData = Data(encodedBytes)
        let decodedData: Data
        if compressed {
            decodedData = try inflateZlib(encodedData)
        } else {
            decodedData = encodedData
        }
        guard let decodedString = String(data: decodedData, encoding: .utf8) else {
            throw DocumentManagerError.invalidImportData
        }
        return decodedString
    }

    private func inflateZlib(_ data: Data) throws -> Data {
        return try data.withUnsafeBytes { (sourceBuffer: UnsafeRawBufferPointer) -> Data in
            guard let sourcePointer = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw DocumentManagerError.invalidImportData
            }
            let bufferSize = 64 * 1024
            let dummyDst = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
            let dummySrc = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
            defer {
                dummyDst.deallocate()
                dummySrc.deallocate()
            }
            var stream = compression_stream(
                dst_ptr: dummyDst,
                dst_size: 0,
                src_ptr: UnsafePointer(dummySrc),
                src_size: 0,
                state: nil
            )
            var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
            guard status != COMPRESSION_STATUS_ERROR else {
                throw DocumentManagerError.invalidImportData
            }
            defer {
                compression_stream_destroy(&stream)
            }
            var output = Data()
            stream.src_ptr = sourcePointer
            stream.src_size = sourceBuffer.count
            let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                outputBuffer.deallocate()
            }
            repeat {
                stream.dst_ptr = outputBuffer
                stream.dst_size = bufferSize
                status = compression_stream_process(&stream, 0)
                let produced = bufferSize - stream.dst_size
                if produced > 0 {
                    output.append(outputBuffer, count: produced)
                }
            } while status == COMPRESSION_STATUS_OK
            if status != COMPRESSION_STATUS_END {
                throw DocumentManagerError.invalidImportData
            }
            return output
        }
    }
}

public enum DocumentManagerError: LocalizedError {
    case missingFolder
    case unindexedFile
    case unsupportedImportType
    case missingEmbeddedScene
    case invalidImportData
    case noCurrentEntry
    case fileAlreadyExists

    public var errorDescription: String? {
        switch self {
        case .missingFolder:
            return "No folder selected for saving documents."
        case .unindexedFile:
            return "Unable to update index for saved document."
        case .unsupportedImportType:
            return "Unsupported file type for import."
        case .missingEmbeddedScene:
            return "No embedded scene data found in the file."
        case .invalidImportData:
            return "Unable to decode the imported scene."
        case .noCurrentEntry:
            return "No file is currently open."
        case .fileAlreadyExists:
            return "A file with that name already exists."
        }
    }
}
