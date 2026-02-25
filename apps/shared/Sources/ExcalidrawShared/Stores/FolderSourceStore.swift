import Dispatch
import Foundation
#if os(macOS)
import Darwin
#endif

public final class FolderSourceStore: ObservableObject {
    @Published public private(set) var sources: [FolderSource] = []
    @Published public private(set) var indexedEntries: [ExcalidrawFileEntry] = []
    @Published public var activeSourceId: UUID? {
        didSet {
            persistActiveSourceId()
        }
    }
    
    public var activeSource: FolderSource? {
        guard let activeSourceId else { return nil }
        return sources.first { $0.id == activeSourceId }
    }
    
    public var activeSourceEntries: [ExcalidrawFileEntry] {
        guard let activeSourceId else { return [] }
        return indexedEntries.filter { $0.folderId == activeSourceId }
    }

    private let userDefaults: UserDefaults
    private let storageKey = "folderSources"
    private let activeSourceKey = "activeFolderSourceId"
    private let sourceHistoryKey = "folderSourceHistory"
    private var activeURLs: [UUID: URL] = [:]
    private let indexStore: ExcalidrawFileIndexStore
    private let indexingQueue: DispatchQueue
    private let fileCoordinator = NSFileCoordinator()
    private var metadataQueries: [UUID: NSMetadataQuery] = [:]
    private var metadataObservers: [UUID: [NSObjectProtocol]] = [:]
    private var metadataRefreshWorkItems: [UUID: DispatchWorkItem] = [:]
#if os(macOS)
    private var watchers: [UUID: DispatchSourceFileSystemObject] = [:]
    private var watcherDescriptors: [UUID: Int32] = [:]
    private var pendingRefreshWorkItems: [UUID: DispatchWorkItem] = [:]
#endif

    public init(
        userDefaults: UserDefaults = .standard,
        indexStore: ExcalidrawFileIndexStore = ExcalidrawJSONFileIndexStore()
    ) {
        self.userDefaults = userDefaults
        self.indexStore = indexStore
        self.indexingQueue = DispatchQueue(label: "com.xexcalidraw.folder-index", qos: .background)
        loadFromDefaults()
        loadActiveSourceId()
        loadIndexFromStore()
        restoreSecurityScopedAccess()
        refreshAllIndexes()
    }

    public enum FolderSourceError: Error {
        case folderAlreadyExists
    }
    
    public func addFolder(url: URL) throws {
        // 检查是否已添加过该目录（标准化路径后比较）
        let standardizedPath = url.standardizedFileURL.path
        for existingSource in sources {
            if let existingURL = resolveURL(for: existingSource),
               existingURL.standardizedFileURL.path == standardizedPath {
                // 目录已存在，设为活跃并返回
                activeSourceId = existingSource.id
                return
            }
        }
        
        let bookmarkData = try createBookmarkData(for: url)
        let displayName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let source = FolderSource(bookmarkData: bookmarkData, displayName: displayName, recursive: true)
        sources.append(source)
        persistSources()
        startAccessing(source: source)
        refreshIndex(for: source)
        // 设置为当前活跃存储库
        activeSourceId = source.id
        addToHistory(sourceId: source.id)
    }
    
    public func switchToSource(id: UUID) {
        guard sources.contains(where: { $0.id == id }) else { return }
        activeSourceId = id
        addToHistory(sourceId: id)
    }
    
    public func getSourceHistory() -> [FolderSource] {
        guard let historyData = userDefaults.data(forKey: sourceHistoryKey),
              let historyIds = try? JSONDecoder().decode([UUID].self, from: historyData) else {
            return []
        }
        // 按历史顺序返回存在的存储库
        return historyIds.compactMap { id in
            sources.first { $0.id == id }
        }
    }
    
    private func addToHistory(sourceId: UUID) {
        var history = getSourceHistory().map { $0.id }
        // 移除已存在的相同ID
        history.removeAll { $0 == sourceId }
        // 添加到开头
        history.insert(sourceId, at: 0)
        // 只保留最近10个
        if history.count > 10 {
            history = Array(history.prefix(10))
        }
        // 保存
        if let data = try? JSONEncoder().encode(history) {
            userDefaults.set(data, forKey: sourceHistoryKey)
        }
    }

    @discardableResult
    public func addICloudDocumentsFolder() throws -> Bool {
        guard let url = defaultICloudDocumentsURL else { return false }
        try ensureICloudDocumentsDirectoryExists(at: url)
        try addFolder(url: url)
        return true
    }

    public func removeFolder(id: UUID) {
        if let url = activeURLs[id] {
            url.stopAccessingSecurityScopedResource()
            activeURLs[id] = nil
        }
        stopMetadataQuery(id: id)
#if os(macOS)
        stopWatching(id: id)
#endif
        sources.removeAll { $0.id == id }
        indexedEntries.removeAll { $0.folderId == id }
        persistSources()
        persistIndexEntries()
        
        // 如果删除的是当前活跃存储库，切换到其他存储库
        if activeSourceId == id {
            activeSourceId = sources.first?.id
        }
    }

    public func resolveURL(for source: FolderSource) -> URL? {
        guard let result = resolveBookmark(for: source.bookmarkData) else {
            return nil
        }
        let (url, stale) = result
        if stale, let updatedData = try? createBookmarkData(for: url) {
            updateBookmark(for: source.id, bookmarkData: updatedData)
        }
        return url
    }

    public func refreshAllIndexes() {
        let sourcesSnapshot = sources
        let existingEntries = indexedEntries
        indexingQueue.async { [weak self] in
            guard let self else { return }
            var aggregated: [ExcalidrawFileEntry] = []
            for source in sourcesSnapshot {
                guard let url = self.resolveURL(for: source) else { continue }
                if let entries = try? self.scanFolder(source: source, url: url) {
                    aggregated.append(contentsOf: entries)
                }
            }
            DispatchQueue.main.async {
                self.indexedEntries = self.mergeEntries(aggregated, existingEntries: existingEntries)
                self.persistIndexEntries()
            }
        }
    }

    private func loadFromDefaults() {
        guard let data = userDefaults.data(forKey: storageKey) else {
            sources = []
            return
        }

        do {
            sources = try JSONDecoder().decode([FolderSource].self, from: data)
        } catch {
            sources = []
        }
    }
    
    private func loadActiveSourceId() {
        var loadedId: UUID? = nil
        if let data = userDefaults.data(forKey: activeSourceKey),
           let decodedId = try? JSONDecoder().decode(UUID?.self, from: data) {
            loadedId = decodedId
        }
        activeSourceId = loadedId
        // 确保activeSourceId在sources中存在
        if let activeId = loadedId, !sources.contains(where: { $0.id == activeId }) {
            activeSourceId = sources.first?.id
        }
    }
    
    private func persistActiveSourceId() {
        guard let data = try? JSONEncoder().encode(activeSourceId) else { return }
        userDefaults.set(data, forKey: activeSourceKey)
    }

    private func loadIndexFromStore() {
        if let entries = try? indexStore.loadEntries() {
            indexedEntries = entries
        } else {
            indexedEntries = []
        }
    }

    private func persistSources() {
        guard let data = try? JSONEncoder().encode(sources) else {
            return
        }
        userDefaults.set(data, forKey: storageKey)
    }

    private func persistIndexEntries() {
        do {
            try indexStore.saveEntries(indexedEntries)
        } catch {
            // Intentionally ignore persistence errors.
        }
    }

    private func restoreSecurityScopedAccess() {
        sources.forEach { startAccessing(source: $0) }
    }

    private func startAccessing(source: FolderSource) {
        guard activeURLs[source.id] == nil, let url = resolveURL(for: source) else {
            return
        }
        if url.startAccessingSecurityScopedResource() {
            activeURLs[source.id] = url
            startMetadataQueryIfNeeded(source: source, url: url)
#if os(macOS)
            startWatching(source: source, url: url)
#endif
        }
    }

    private func createBookmarkData(for url: URL) throws -> Data {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        #if os(macOS)
        if let data = try? url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return data
        }
        return try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return try url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    private func updateBookmark(for id: UUID, bookmarkData: Data) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else {
            return
        }
        sources[index].bookmarkData = bookmarkData
        persistSources()
    }

    private func refreshIndex(for source: FolderSource) {
        guard let url = resolveURL(for: source) else { return }
        indexingQueue.async { [weak self] in
            guard let self else { return }
            let entries = (try? self.scanFolder(source: source, url: url)) ?? []
            DispatchQueue.main.async {
                self.updateIndexEntries(folderId: source.id, entries: entries)
            }
        }
    }

    private func updateIndexEntries(folderId: UUID, entries: [ExcalidrawFileEntry]) {
        let existingEntries = indexedEntries.filter { $0.folderId == folderId }
        let merged = mergeEntries(entries, existingEntries: existingEntries)
        indexedEntries.removeAll { $0.folderId == folderId }
        indexedEntries.append(contentsOf: merged)
        persistIndexEntries()
    }

    private func scanFolder(source: FolderSource, url: URL) throws -> [ExcalidrawFileEntry] {
        var coordinatedError: NSError?
        var scanError: NSError?
        var results: [ExcalidrawFileEntry] = []
        fileCoordinator.coordinate(
            readingItemAt: url,
            options: [.withoutChanges],
            error: &coordinatedError
        ) { coordinatedURL in
            do {
                results = try scanFolderContents(source: source, url: coordinatedURL)
            } catch {
                scanError = error as NSError
            }
        }
        if let error = coordinatedError ?? scanError {
            throw error
        }
        return results
    }

    private func scanFolderContents(source: FolderSource, url: URL) throws -> [ExcalidrawFileEntry] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return [] }
        var results: [ExcalidrawFileEntry] = []
        if source.recursive {
            let enumerator = manager.enumerator(
                at: url,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            while let itemURL = enumerator?.nextObject() as? URL {
                try appendEntryIfNeeded(source: source, rootURL: url, itemURL: itemURL, results: &results)
            }
        } else {
            let contents = try manager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            for itemURL in contents {
                try appendEntryIfNeeded(source: source, rootURL: url, itemURL: itemURL, results: &results)
            }
        }
        return results
    }

    private func appendEntryIfNeeded(
        source: FolderSource,
        rootURL: URL,
        itemURL: URL,
        results: inout [ExcalidrawFileEntry]
    ) throws {
        let fileName = itemURL.lastPathComponent.lowercased()
        guard fileName.hasSuffix(".excalidraw") || fileName.hasSuffix(".excalidraw.json") else {
            return
        }
        let resourceValues = try itemURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
        guard resourceValues.isRegularFile ?? true else { return }
        let modifiedAt = resourceValues.contentModificationDate ?? Date()
        let fileSize = Int64(resourceValues.fileSize ?? 0)
        let relativePath = itemURL.path.replacingOccurrences(
            of: rootURL.path.appending("/"),
            with: ""
        )
        let entry = ExcalidrawFileEntry(
            folderId: source.id,
            relativePath: relativePath,
            fileName: itemURL.lastPathComponent,
            fileURL: itemURL,
            modifiedAt: modifiedAt,
            fileSize: fileSize
        )
        results.append(entry)
    }

    public var defaultICloudDocumentsURL: URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return containerURL.appendingPathComponent("Documents", isDirectory: true)
    }

    private func ensureICloudDocumentsDirectoryExists(at url: URL) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: url.path) else { return }
        try manager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    private func isICloudURL(_ url: URL) -> Bool {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return false
        }
        let basePath = containerURL.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        return targetPath.hasPrefix(basePath)
    }

    private func startMetadataQueryIfNeeded(source: FolderSource, url: URL) {
        guard metadataQueries[source.id] == nil, isICloudURL(url) else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [url]
        query.predicate = NSPredicate(
            format: "%K ENDSWITH[c] %@ OR %K ENDSWITH[c] %@",
            NSMetadataItemFSNameKey,
            ".excalidraw",
            NSMetadataItemFSNameKey,
            ".excalidraw.json"
        )
        let notificationCenter = NotificationCenter.default
        var observers: [NSObjectProtocol] = []
        observers.append(notificationCenter.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleMetadataRefresh(for: source)
        })
        observers.append(notificationCenter.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleMetadataRefresh(for: source)
        })
        metadataObservers[source.id] = observers
        metadataQueries[source.id] = query
        query.start()
    }

    private func stopMetadataQuery(id: UUID) {
        metadataRefreshWorkItems[id]?.cancel()
        metadataRefreshWorkItems[id] = nil
        if let observers = metadataObservers[id] {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
        metadataObservers[id] = nil
        if let query = metadataQueries[id] {
            query.stop()
        }
        metadataQueries[id] = nil
    }

    private func scheduleMetadataRefresh(for source: FolderSource) {
        metadataRefreshWorkItems[source.id]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshIndex(for: source)
        }
        metadataRefreshWorkItems[source.id] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func mergeEntries(
        _ newEntries: [ExcalidrawFileEntry],
        existingEntries: [ExcalidrawFileEntry]
    ) -> [ExcalidrawFileEntry] {
        // 使用 Dictionary 去重，保留最后出现的条目
        var existingLookup: [URL: ExcalidrawFileEntry] = [:]
        for entry in existingEntries {
            existingLookup[entry.fileURL] = entry
        }
        return newEntries.map { entry in
            guard let existing = existingLookup[entry.fileURL] else { return entry }
            return ExcalidrawFileEntry(
                id: existing.id,
                folderId: entry.folderId,
                relativePath: entry.relativePath,
                fileName: entry.fileName,
                fileURL: entry.fileURL,
                modifiedAt: entry.modifiedAt,
                fileSize: entry.fileSize,
                lastOpenedAt: existing.lastOpenedAt,
                thumbnailPath: existing.thumbnailPath
            )
        }
    }

    @discardableResult
    public func updateLastOpenedAt(for fileURL: URL, date: Date = Date()) -> ExcalidrawFileEntry? {
        guard let index = indexedEntries.firstIndex(where: { $0.fileURL == fileURL }) else {
            return nil
        }
        let existing = indexedEntries[index]
        let updated = ExcalidrawFileEntry(
            id: existing.id,
            folderId: existing.folderId,
            relativePath: existing.relativePath,
            fileName: existing.fileName,
            fileURL: existing.fileURL,
            modifiedAt: existing.modifiedAt,
            fileSize: existing.fileSize,
            lastOpenedAt: date,
            thumbnailPath: existing.thumbnailPath
        )
        indexedEntries[index] = updated
        persistIndexEntries()
        return updated
    }

    @discardableResult
    public func updateEntryAfterSave(for fileURL: URL, date: Date = Date()) -> ExcalidrawFileEntry? {
        guard let index = indexedEntries.firstIndex(where: { $0.fileURL == fileURL }) else {
            return nil
        }
        let existing = indexedEntries[index]
        let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modifiedAt = resourceValues?.contentModificationDate ?? existing.modifiedAt
        let fileSize = Int64(resourceValues?.fileSize ?? Int(existing.fileSize))
        let updated = ExcalidrawFileEntry(
            id: existing.id,
            folderId: existing.folderId,
            relativePath: existing.relativePath,
            fileName: existing.fileName,
            fileURL: existing.fileURL,
            modifiedAt: modifiedAt,
            fileSize: fileSize,
            lastOpenedAt: date,
            thumbnailPath: existing.thumbnailPath
        )
        indexedEntries[index] = updated
        persistIndexEntries()
        return updated
    }

    @discardableResult
    public func upsertEntry(
        for fileURL: URL,
        folderId: UUID,
        rootURL: URL,
        lastOpenedAt: Date? = nil
    ) -> ExcalidrawFileEntry? {
        let normalizedName = fileURL.lastPathComponent.lowercased()
        guard normalizedName.hasSuffix(".excalidraw") || normalizedName.hasSuffix(".excalidraw.json") else { return nil }
        let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
        guard resourceValues?.isRegularFile ?? true else { return nil }
        let modifiedAt = resourceValues?.contentModificationDate ?? Date()
        let fileSize = Int64(resourceValues?.fileSize ?? 0)
        let relativePath = fileURL.path.replacingOccurrences(
            of: rootURL.path.appending("/"),
            with: ""
        )
        let fileName = fileURL.lastPathComponent
        if let index = indexedEntries.firstIndex(where: { $0.fileURL == fileURL }) {
            let existing = indexedEntries[index]
            let updated = ExcalidrawFileEntry(
                id: existing.id,
                folderId: folderId,
                relativePath: relativePath,
                fileName: fileName,
                fileURL: fileURL,
                modifiedAt: modifiedAt,
                fileSize: fileSize,
                lastOpenedAt: lastOpenedAt ?? existing.lastOpenedAt,
                thumbnailPath: existing.thumbnailPath
            )
            indexedEntries[index] = updated
            persistIndexEntries()
            return updated
        }
        let entry = ExcalidrawFileEntry(
            folderId: folderId,
            relativePath: relativePath,
            fileName: fileName,
            fileURL: fileURL,
            modifiedAt: modifiedAt,
            fileSize: fileSize,
            lastOpenedAt: lastOpenedAt
        )
        indexedEntries.append(entry)
        persistIndexEntries()
        return entry
    }

    public func removeEntry(id: UUID) {
        indexedEntries.removeAll { $0.id == id }
        persistIndexEntries()
    }

    public func updateEntryAfterRename(id: UUID, newFileURL: URL, newFileName: String) {
        guard let index = indexedEntries.firstIndex(where: { $0.id == id }) else { return }
        let existing = indexedEntries[index]
        let updated = ExcalidrawFileEntry(
            id: existing.id,
            folderId: existing.folderId,
            relativePath: newFileURL.lastPathComponent,
            fileName: newFileName,
            fileURL: newFileURL,
            modifiedAt: Date(),
            fileSize: existing.fileSize,
            lastOpenedAt: existing.lastOpenedAt,
            thumbnailPath: existing.thumbnailPath
        )
        indexedEntries[index] = updated
        persistIndexEntries()
    }

#if os(macOS)
    private func startWatching(source: FolderSource, url: URL) {
        guard watchers[source.id] == nil else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let sourceWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend],
            queue: DispatchQueue.main
        )
        sourceWatcher.setEventHandler { [weak self] in
            self?.scheduleRefresh(for: source)
        }
        sourceWatcher.setCancelHandler { [weak self] in
            close(descriptor)
            self?.watcherDescriptors[source.id] = nil
        }
        watcherDescriptors[source.id] = descriptor
        watchers[source.id] = sourceWatcher
        sourceWatcher.resume()
    }

    private func scheduleRefresh(for source: FolderSource) {
        pendingRefreshWorkItems[source.id]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshIndex(for: source)
        }
        pendingRefreshWorkItems[source.id] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func stopWatching(id: UUID) {
        pendingRefreshWorkItems[id]?.cancel()
        pendingRefreshWorkItems[id] = nil
        watchers[id]?.cancel()
        watchers[id] = nil
    }
#endif

    private var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(iOS)
        return [.minimalBookmark]
        #else
        return [.withSecurityScope]
        #endif
    }

    private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(iOS)
        return []
        #else
        return [.withSecurityScope]
        #endif
    }

    private func resolveBookmark(for data: Data) -> (URL, Bool)? {
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            return (url, stale)
        }
        #if os(macOS)
        var fallbackStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &fallbackStale
        ) {
            return (url, fallbackStale)
        }
        #endif
        return nil
    }
}
