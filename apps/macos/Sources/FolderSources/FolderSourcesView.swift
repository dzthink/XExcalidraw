import SwiftUI

import ExcalidrawShared

struct FolderSourcesView: View {
    @StateObject private var store = FolderSourceStore()

    var body: some View {
        List(selection: .constant(Set<UUID>())) {
            Section("Folders") {
                ForEach(store.sources) { source in
                    Text(source.displayName)
                        .contextMenu {
                            Button("Remove") {
                                store.removeFolder(id: source.id)
                            }
                        }
                }
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
        .listStyle(.sidebar)
        .navigationTitle("Folder Sources")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openFolderPicker()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try store.addFolder(url: url)
            } catch {
                // Handle errors in the caller if needed.
            }
        }
    }
}
