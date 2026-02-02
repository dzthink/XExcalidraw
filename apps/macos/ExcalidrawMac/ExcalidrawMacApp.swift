import SwiftUI
import ExcalidrawShared
import WebKit

@main
struct ExcalidrawMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
    }
}

struct ContentView: View {
    @StateObject private var documentManager: DocumentManager
    @StateObject private var viewModel: WebCanvasViewModel

    init() {
        let documentManager = DocumentManager()
        _documentManager = StateObject(wrappedValue: documentManager)
        _viewModel = StateObject(wrappedValue: WebCanvasViewModel(documentManager: documentManager))
    }

    var body: some View {
        NavigationSplitView {
            List {
                Section("Folders") {
                    ForEach(documentManager.sources) { source in
                        Text(source.displayName)
                            .contextMenu {
                                Button("Remove") {
                                    documentManager.removeFolder(id: source.id)
                                }
                            }
                    }
                }
                Section {
                    let sortedEntries = documentManager.indexedEntries.sorted {
                        let lhsDate = $0.lastOpenedAt ?? $0.modifiedAt
                        let rhsDate = $1.lastOpenedAt ?? $1.modifiedAt
                        return lhsDate > rhsDate
                    }
                    ForEach(sortedEntries) { entry in
                        Button {
                            viewModel.open(entry: entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.fileName)
                                    .font(.headline)
                                if let lastOpenedAt = entry.lastOpenedAt {
                                    Text("Last opened \(lastOpenedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Never opened")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Documents")
                } footer: {
                    Text("Index: \(documentManager.indexStatus.description)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openFolderPicker()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        documentManager.refreshIndexes()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        } detail: {
            WebCanvasView(webView: viewModel.webView)
                .background(Color(nsColor: .windowBackgroundColor))
                .navigationTitle("Excalidraw")
                .overlay(alignment: .bottomLeading) {
                    Text(viewModel.statusText)
                        .font(.caption)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
        }
        .onAppear {
            viewModel.load()
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
                try documentManager.addFolder(url: url)
            } catch {
                // Handle errors in the caller if needed.
            }
        }
    }
}

final class WebCanvasViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    @Published var statusText: String = "Ready"
    let webView: WKWebView

    private let messageHandlerName = "bridge"
    private var didSendInitialScene = false
    private let documentManager: DocumentManager

    init(documentManager: DocumentManager) {
        self.documentManager = documentManager
        let contentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        contentController.add(self, name: messageHandlerName)
        webView.navigationDelegate = self
    }

    func load() {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else if let devURL = URL(string: "http://localhost:5173") {
            webView.load(URLRequest(url: devURL))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didSendInitialScene else { return }
        didSendInitialScene = true
        loadInitialScene()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == messageHandlerName else { return }
        if let payloadString = message.body as? String {
            handleIncomingMessage(payloadString)
        }
    }

    private func handleIncomingMessage(_ payloadString: String) {
        guard
            let data = payloadString.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String,
            let payload = json["payload"] as? [String: Any]
        else {
            statusText = "Invalid bridge message"
            return
        }

        if type == "saveScene" {
            handleSave(payload: payload)
        } else if type == "didChange" {
            statusText = "Unsaved changes"
        } else if type == "exportResult" {
            statusText = "Export received"
        }
    }

    private func handleSave(payload: [String: Any]) {
        guard
            let docId = payload["docId"] as? String,
            let sceneJson = payload["sceneJson"]
        else {
            statusText = "Save failed"
            return
        }

        documentManager.saveScene(docId: docId, sceneJson: sceneJson) { [weak self] result in
            switch result {
            case .success(let entry):
                self?.statusText = "Saved \(entry.fileName)"
            case .failure(let error):
                self?.statusText = "Save error: \(error.localizedDescription)"
            }
        }
    }

    func open(entry: ExcalidrawFileEntry) {
        do {
            let scene = try documentManager.open(entry: entry)
            send(type: "loadScene", payload: [
                "docId": scene.docId,
                "sceneJson": scene.sceneJson,
                "readOnly": scene.readOnly
            ])
            statusText = "Loaded \(entry.fileName)"
        } catch {
            statusText = "Load error: \(error.localizedDescription)"
        }
    }

    private func loadInitialScene() {
        if let entry = documentManager.mostRecentEntry() {
            open(entry: entry)
            return
        }
        let docId = UUID().uuidString
        let payload: [String: Any] = [
            "docId": docId,
            "sceneJson": ["elements": [], "appState": [:]],
            "readOnly": false
        ]
        send(type: "loadScene", payload: payload)
        statusText = "Loaded new scene"
    }

    private func send(type: String, payload: [String: Any]) {
        let envelope: [String: Any] = [
            "version": "1.0",
            "type": type,
            "payload": payload
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: envelope),
            let jsonString = String(data: data, encoding: .utf8)
        else { return }
        let js = "window.bridgeDispatch && window.bridgeDispatch(\(jsonString.debugDescription))"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}

struct WebCanvasView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
