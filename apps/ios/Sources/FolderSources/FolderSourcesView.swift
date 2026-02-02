import SwiftUI

import ExcalidrawShared

struct FolderSourcesView: View {
    @StateObject private var store = FolderSourceStore()
    @State private var isShowingPicker = false

    var body: some View {
        NavigationView {
            List {
                ForEach(store.sources) { source in
                    Text(source.displayName)
                }
                .onDelete(perform: deleteSources)
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
            }
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
