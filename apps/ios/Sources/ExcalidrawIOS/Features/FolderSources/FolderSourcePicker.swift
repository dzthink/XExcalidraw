#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

import ExcalidrawShared

struct FolderSourcePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let store: FolderSourceStore

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        controller.allowsMultipleSelection = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let store: FolderSourceStore
        private let dismiss: DismissAction

        init(store: FolderSourceStore, dismiss: DismissAction) {
            self.store = store
            self.dismiss = dismiss
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            defer { dismiss() }
            guard let url = urls.first else { return }
            do {
                try store.addFolder(url: url)
            } catch {
                // Handle errors in the caller if needed.
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            dismiss()
        }
    }
}
#else
import SwiftUI
import ExcalidrawShared

struct FolderSourcePicker: View {
    let store: FolderSourceStore

    var body: some View {
        Text("Folder picker is available on iOS only.")
            .padding()
    }
}
#endif
