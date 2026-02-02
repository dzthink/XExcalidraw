import Foundation

public enum ExcalidrawIndexSortOrder {
    case directory
    case name
    case modifiedAt
}

public final class ExcalidrawIndexer {
    private let folderURL: URL
    private let store: ExcalidrawIndexStore
    private let isRecursive: Bool
    private let queue: DispatchQueue

    public init(folderURL: URL, store: ExcalidrawIndexStore, isRecursive: Bool) {
        self.folderURL = folderURL
        self.store = store
        self.isRecursive = isRecursive
        self.queue = DispatchQueue(label: "com.xexcalidraw.indexer", qos: .background)
    }

    public func startBackgroundScan() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let entries = try self.scanFolder()
                try self.store.saveEntries(entries)
            } catch {
                // Intentionally ignore background indexing errors.
            }
        }
    }

    public func scanFolder() throws -> [ExcalidrawFileEntry] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: folderURL.path) else {
            return []
        }

        var results: [ExcalidrawFileEntry] = []
        if isRecursive {
            let enumerator = manager.enumerator(at: folderURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            while let url = enumerator?.nextObject() as? URL {
                try appendEntryIfNeeded(for: url, to: &results)
            }
        } else {
            let contents = try manager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            for url in contents {
                try appendEntryIfNeeded(for: url, to: &results)
            }
        }

        return results
    }

    public func loadIndex() throws -> [ExcalidrawFileEntry] {
        return try store.loadEntries()
    }

    public func queryIndex(sortedBy sortOrder: ExcalidrawIndexSortOrder) throws -> [ExcalidrawFileEntry] {
        let entries = try store.loadEntries()
        return sort(entries, by: sortOrder)
    }

    public func queryIndex(inDirectory directoryPath: String?, sortedBy sortOrder: ExcalidrawIndexSortOrder) throws -> [ExcalidrawFileEntry] {
        let entries = try store.loadEntries()
        let filtered: [ExcalidrawFileEntry]
        if let directoryPath {
            filtered = entries.filter { $0.directoryPath == directoryPath }
        } else {
            filtered = entries
        }
        return sort(filtered, by: sortOrder)
    }

    public func sort(_ entries: [ExcalidrawFileEntry], by sortOrder: ExcalidrawIndexSortOrder) -> [ExcalidrawFileEntry] {
        switch sortOrder {
        case .directory:
            return entries.sorted { lhs, rhs in
                if lhs.directoryPath == rhs.directoryPath {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.directoryPath.localizedCaseInsensitiveCompare(rhs.directoryPath) == .orderedAscending
            }
        case .name:
            return entries.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .modifiedAt:
            return entries.sorted { lhs, rhs in
                lhs.modifiedAt > rhs.modifiedAt
            }
        }
    }

    private func appendEntryIfNeeded(for url: URL, to results: inout [ExcalidrawFileEntry]) throws {
        guard url.pathExtension.lowercased() == "excalidraw" else { return }
        let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey])
        let modifiedAt = resourceValues.contentModificationDate ?? Date()
        let directoryPath = url.deletingLastPathComponent().path
        let entry = ExcalidrawFileEntry(
            name: url.deletingPathExtension().lastPathComponent,
            directoryPath: directoryPath,
            filePath: url.path,
            modifiedAt: modifiedAt
        )
        results.append(entry)
    }
}
