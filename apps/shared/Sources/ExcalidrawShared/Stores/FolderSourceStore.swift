import Dispatch
import Foundation
#if os(macOS)
import Darwin
#endif

public final class FolderSourceStore: ObservableObject {
    @Published public private(set) var sources: [FolderSource] = []
    @Published public private(set) var indexedEntries: [ExcalidrawFileEntry] = []

    private let userDefaults: UserDefaults
    private let storageKey = "folderSources"
    private var activeURLs: [UUID: URL] = [:]
    private let indexStore: ExcalidrawFileIndexStore
    private let indexingQueue: DispatchQueue
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
        loadIndexFromStore()
        restoreSecurityScopedAccess()
        refreshAllIndexes()
    }

    public func addFolder(url: URL) throws {
        let bookmarkData = try createBookmarkData(for: url)
        let displayName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let source = FolderSource(displayName: displayName, bookmarkData: bookmarkData, recursive: true)
        sources.append(source)
        persistSources()
        startAccessing(source: source)
        refreshIndex(for: source)
    }

    public func removeFolder(id: UUID) {
        if let url = activeURLs[id] {
            url.stopAccessingSecurityScopedResource()
            activeURLs[id] = nil
        }
#if os(macOS)
        stopWatching(id: id)
#endif
        sources.removeAll { $0.id == id }
        indexedEntries.removeAll { $0.folderId == id }
        persistSources()
        persistIndexEntries()
    }

    public func resolveURL(for source: FolderSource) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: source.bookmarkData,
            options: bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }

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

        return try url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
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
        guard itemURL.pathExtension.lowercased() == "excalidraw" else { return }
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

    private func mergeEntries(
        _ newEntries: [ExcalidrawFileEntry],
        existingEntries: [ExcalidrawFileEntry]
    ) -> [ExcalidrawFileEntry] {
        let existingLookup = Dictionary(uniqueKeysWithValues: existingEntries.map { ($0.fileURL, $0) })
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
        guard fileURL.pathExtension.lowercased() == "excalidraw" else { return nil }
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
        return [.minimalBookmark, .withSecurityScope]
        #else
        return [.withSecurityScope]
        #endif
    }

    private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        return [.withSecurityScope]
    }
}
