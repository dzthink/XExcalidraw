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

    public func importScene(
        from fileURL: URL,
        completion: @escaping (Result<ExcalidrawFileEntry, Error>) -> Void
    ) {
        saveQueue.async { [weak self] in
            guard let self else { return }
            do {
                let sceneJson = try self.loadImportScene(from: fileURL)
                let targetName = self.makeImportDocumentName(from: fileURL)
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

    public func createBlankDocument(
        completion: @escaping (Result<DocumentScene, Error>) -> Void
    ) {
        saveQueue.async { [weak self] in
            guard let self else { return }
            guard let (source, folderURL) = self.defaultFolderSource() else {
                DispatchQueue.main.async {
                    completion(.failure(DocumentManagerError.missingFolder))
                }
                return
            }
            let fileURL = self.makeUntitledFileURL(in: folderURL)
            let sceneJson: [String: Any] = [
                "elements": [],
                "appState": [:]
            ]
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: sceneJson, options: [.prettyPrinted])
                try jsonData.write(to: fileURL, options: [.atomic])
                guard let entry = self.store.upsertEntry(
                    for: fileURL,
                    folderId: source.id,
                    rootURL: folderURL,
                    lastOpenedAt: Date()
                ) else {
                    DispatchQueue.main.async {
                        completion(.failure(DocumentManagerError.unindexedFile))
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.currentEntry = entry
                    self.activeFolderId = source.id
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

    private func loadImportScene(from fileURL: URL) throws -> Any {
        let fileName = fileURL.lastPathComponent.lowercased()
        let fileExtension = fileURL.pathExtension.lowercased()
        let data = try Data(contentsOf: fileURL)
        if fileExtension == "excalidraw" {
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

    private func makeUntitledFileURL(in folderURL: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let baseName = "Untitled-\(timestamp)"
        var candidate = baseName
        var counter = 1
        var fileURL = folderURL.appendingPathComponent("\(candidate).excalidraw")
        while FileManager.default.fileExists(atPath: fileURL.path) {
            candidate = "\(baseName)-\(counter)"
            counter += 1
            fileURL = folderURL.appendingPathComponent("\(candidate).excalidraw")
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
        }
    }
}
