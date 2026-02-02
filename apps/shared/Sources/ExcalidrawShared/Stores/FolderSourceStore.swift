import Foundation

public final class FolderSourceStore: ObservableObject {
    @Published public private(set) var sources: [FolderSource] = []

    private let userDefaults: UserDefaults
    private let storageKey = "folderSources"
    private var activeURLs: [UUID: URL] = [:]

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadFromDefaults()
        restoreSecurityScopedAccess()
    }

    public func addFolder(url: URL) throws {
        let bookmarkData = try createBookmarkData(for: url)
        let displayName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let source = FolderSource(displayName: displayName, bookmarkData: bookmarkData)
        sources.append(source)
        persistSources()
        startAccessing(source: source)
    }

    public func removeFolder(id: UUID) {
        if let url = activeURLs[id] {
            url.stopAccessingSecurityScopedResource()
            activeURLs[id] = nil
        }
        sources.removeAll { $0.id == id }
        persistSources()
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

    private func persistSources() {
        guard let data = try? JSONEncoder().encode(sources) else {
            return
        }
        userDefaults.set(data, forKey: storageKey)
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
