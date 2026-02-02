import SwiftUI
import ExcalidrawShared
import UIKit
import WebKit

@main
struct ExcalidrawIOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var documentManager: DocumentManager
    @StateObject private var viewModel: WebCanvasViewModel
    @State private var isShowingPicker = false

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
                    }
                    .onDelete(perform: deleteSources)
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
            .navigationTitle("Documents")
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
                        documentManager.refreshIndexes()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                documentManager.refreshIndexes()
            }
            .sheet(isPresented: $isShowingPicker) {
                FolderSourcePicker(store: documentManager.folderStore)
            }
        } detail: {
            WebCanvasView(webView: viewModel.webView)
                .ignoresSafeArea()
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

    private func deleteSources(at offsets: IndexSet) {
        for index in offsets {
            let source = documentManager.sources[index]
            documentManager.removeFolder(id: source.id)
        }
    }
}

final class WebCanvasViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    @Published var statusText: String = "Ready"
    let webView: WKWebView

    private let messageHandlerName = "bridge"
    private var didSendInitialScene = false
    private let documentManager: DocumentManager
    private let aiModule: AIModule

    init(documentManager: DocumentManager, aiModule: AIModule = EmptyAIModule()) {
        self.documentManager = documentManager
        self.aiModule = aiModule
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
            handleExport(payload: payload)
        } else if type == "requestAI" {
            handleRequestAI(payload: payload)
        }
    }

    private func handleExport(payload: [String: Any]) {
        guard
            let format = payload["format"] as? String,
            let dataBase64 = payload["dataBase64"] as? String,
            let exportData = Data(base64Encoded: dataBase64),
            let fileExtension = fileExtension(for: format)
        else {
            statusText = "Export failed"
            return
        }

        do {
            let exportDirectory = try resolveExportDirectory()
            let fileName = makeExportFileName(extension: fileExtension)
            let fileURL = exportDirectory.appendingPathComponent(fileName)
            try exportData.write(to: fileURL, options: [.atomic])
            statusText = "Exported \(fileName)"
            presentShareSheet(for: fileURL)
        } catch {
            statusText = "Export error: \(error.localizedDescription)"
        }
    }

    private func resolveExportDirectory() throws -> URL {
        guard let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw DocumentManagerError.missingFolder
        }
        let exportURL = baseURL.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportURL, withIntermediateDirectories: true)
        return exportURL
    }

    private func makeExportFileName(extension fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let baseName = documentManager.currentEntry?
            .fileURL
            .deletingPathExtension()
            .lastPathComponent ?? "Excalidraw"
        return "\(baseName)-\(timestamp).\(fileExtension)"
    }

    private func fileExtension(for format: String) -> String? {
        switch format.lowercased() {
        case "png":
            return "png"
        case "svg":
            return "svg"
        case "json":
            return "json"
        default:
            return nil
        }
    }

    private func presentShareSheet(for fileURL: URL) {
        DispatchQueue.main.async {
            guard
                let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
            else {
                return
            }
            let activityController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            rootViewController.present(activityController, animated: true)
        }
    }

    private func handleRequestAI(payload: [String: Any]) {
        let docId = payload["docId"] as? String ?? UUID().uuidString
        let prompt = payload["prompt"] as? String
        statusText = "Generating AI scene..."
        aiModule.generateScene(docId: docId, prompt: prompt) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sceneJson):
                    self?.send(type: "loadScene", payload: [
                        "docId": docId,
                        "sceneJson": sceneJson,
                        "readOnly": false
                    ])
                    self?.statusText = "AI scene loaded"
                case .failure(let error):
                    self?.statusText = "AI error: \(error.localizedDescription)"
                }
            }
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

struct WebCanvasView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
