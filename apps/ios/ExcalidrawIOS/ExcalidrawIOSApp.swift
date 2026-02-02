import SwiftUI
import ExcalidrawShared
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
    @StateObject private var viewModel = WebCanvasViewModel()

    var body: some View {
        NavigationView {
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
}

final class WebCanvasViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    @Published var statusText: String = "Ready"
    let webView: WKWebView

    private let messageHandlerName = "bridge"
    private var didSendInitialScene = false

    override init() {
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
        sendLoadScene()
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

        let fileURL = storageDirectory().appendingPathComponent("\(docId).excalidraw")
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: sceneJson, options: [.prettyPrinted])
            try jsonData.write(to: fileURL, options: [.atomic])
            statusText = "Saved \(fileURL.lastPathComponent)"
        } catch {
            statusText = "Save error: \(error.localizedDescription)"
        }
    }

    private func storageDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("Excalidraw", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private func sendLoadScene() {
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
