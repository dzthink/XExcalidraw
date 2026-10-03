import Foundation

/// Serial disk writes keep encoding and file IO away from UI state mutations.
final class IndexPersistenceWriter {
    private let store: ExcalidrawFileIndexStore
    private let queue = DispatchQueue(label: "com.xexcalidraw.index-persistence", qos: .utility)
    private let lock = NSLock()
    private var pending: [ExcalidrawFileEntry]?
    private var running = false

    init(store: ExcalidrawFileIndexStore) { self.store = store }

    func schedule(_ entries: [ExcalidrawFileEntry]) {
        lock.lock()
        pending = entries
        let start = !running
        running = true
        lock.unlock()
        if start { queue.async { self.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let entries = pending else {
                running = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            try? store.saveEntries(entries)
        }
    }
}
