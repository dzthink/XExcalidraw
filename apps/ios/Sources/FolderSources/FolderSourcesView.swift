import SwiftUI

import ExcalidrawShared

struct FolderSourcesView: View {
    @StateObject private var store = FolderSourceStore()
    @State private var isShowingPicker = false

    var body: some View {
        NavigationView {
            List {
                Section("Folders") {
                    ForEach(store.sources) { source in
                        Text(source.displayName)
                    }
                    .onDelete(perform: deleteSources)
                }
                Section("Indexed Files") {
                    let folderLookup = Dictionary(uniqueKeysWithValues: store.sources.map { ($0.id, $0.displayName) })
                    ForEach(store.indexedEntries.sorted(by: { $0.modifiedAt > $1.modifiedAt })) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.fileName)
                                .font(.headline)
                            Text(folderLookup[entry.folderId, default: "Unknown Folder"])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Folder Sources")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // TODO: Consider NSFileCoordinator on iOS for automatic file updates.
                        store.refreshAllIndexes()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .refreshable {
            store.refreshAllIndexes()
        }
        .sheet(isPresented: $isShowingPicker) {
            FolderSourcePicker(store: store)
        }
    }

    private func deleteSources(at offsets: IndexSet) {
        for index in offsets {
            let source = store.sources[index]
            store.removeFolder(id: source.id)
        }
    }
}
