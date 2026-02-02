import SwiftUI

import ExcalidrawShared

struct FolderSourcesView: View {
    @StateObject private var store = FolderSourceStore()

    var body: some View {
        List(selection: .constant(Set<UUID>())) {
            ForEach(store.sources) { source in
                Text(source.displayName)
                    .contextMenu {
                        Button("Remove") {
                            store.removeFolder(id: source.id)
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
