import SwiftUI
import AppKit
import ExcalidrawShared
import UniformTypeIdentifiers
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
    @State private var didStartUp = false
    @State private var isShowingDraftAlert = false
    @State private var pendingDraft: DocumentDraft?
    @State private var selectedEntryId: UUID?
    @State private var entryToRename: ExcalidrawFileEntry?
    @State private var newFileName: String = ""
    @State private var isShowingRenameAlert = false
    @State private var fileTreeRoot: FileTreeNode?
    @State private var lastActiveFolderId: UUID?

    init() {
        let documentManager = DocumentManager()
        let viewModel = WebCanvasViewModel(documentManager: documentManager)
        viewModel.prewarm()
        _documentManager = StateObject(wrappedValue: documentManager)
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    private func updateFileTreeIfNeeded() {
        guard let activeFolderId = documentManager.activeFolderId else {
            fileTreeRoot = nil
            lastActiveFolderId = nil
            return
        }
        
        // Only rebuild if folder changed or not built yet
        if activeFolderId != lastActiveFolderId || fileTreeRoot == nil {
            if let source = documentManager.sources.first(where: { $0.id == activeFolderId }) {
                let entries = filteredEntries
                fileTreeRoot = FileTreeBuilder.buildTree(
                    entries: entries,
                    folderName: source.displayName
                )
                lastActiveFolderId = activeFolderId
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            ZStack {
                WebCanvasView(webView: viewModel.webView)
                    .background(Color(nsColor: .windowBackgroundColor))
                if !viewModel.isCanvasReady {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading canvas…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
            .navigationTitle("Excalidraw")
        }
        .task {
            guard !didStartUp else { return }
            didStartUp = true
            viewModel.load()
            ensureActiveFolder()
        }
        .onChange(of: documentManager.sources) { _ in
            ensureActiveFolder()
            documentManager.refreshIndexes()
        }
        .onChange(of: documentManager.pendingDraft) { draft in
            guard let draft else { return }
            if pendingDraft == nil {
                pendingDraft = draft
                isShowingDraftAlert = true
            }
        }
        .alert("检测到未保存的内容", isPresented: $isShowingDraftAlert) {
            Button("恢复") {
                if let draft = documentManager.consumePendingDraft() {
                    viewModel.restoreDraft(draft)
                }
                pendingDraft = nil
            }
            Button("放弃", role: .destructive) {
                documentManager.discardPendingDraft()
                pendingDraft = nil
            }
        } message: {
            if let draft = pendingDraft {
                Text("是否恢复 \(draft.savedAt.formatted(date: .abbreviated, time: .shortened)) 的临时保存？")
            } else {
                Text("是否恢复临时保存的画布？")
            }
        }
        .alert("重命名文件", isPresented: $isShowingRenameAlert) {
            TextField("文件名", text: $newFileName)
            Button("取消", role: .cancel) {
                entryToRename = nil
            }
            Button("确定") {
                if let entry = entryToRename {
                    performRename(entry: entry, newName: newFileName)
                }
                entryToRename = nil
            }
        } message: {
            Text("输入新文件名")
        }
    }

    private var folderSelection: Binding<UUID?> {
        Binding(
            get: { documentManager.activeFolderId },
            set: { newValue in
                if let newValue {
                    documentManager.activeFolderId = newValue
                    return
                }
                if documentManager.sources.isEmpty {
                    documentManager.activeFolderId = nil
                }
            }
        )
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

    private func ensureActiveFolder() {
        guard let activeFolderId = documentManager.activeFolderId else {
            documentManager.activeFolderId = documentManager.sources.first?.id
            return
        }
        if !documentManager.sources.contains(where: { $0.id == activeFolderId }) {
            documentManager.activeFolderId = documentManager.sources.first?.id
        }
    }

    private var filteredEntries: [ExcalidrawFileEntry] {
        guard let activeFolderId = documentManager.activeFolderId else { return [] }
        let entries = documentManager.indexedEntries.filter { $0.folderId == activeFolderId }
        // Sort alphabetically by file name
        return entries.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    private func deleteEntry(_ entry: ExcalidrawFileEntry) {
        do {
            try FileManager.default.removeItem(at: entry.fileURL)
            documentManager.folderStore.removeEntry(id: entry.id)
            if selectedEntryId == entry.id {
                selectedEntryId = nil
            }
        } catch {
            // Handle error silently
        }
    }

    private func renameEntry(_ entry: ExcalidrawFileEntry) {
        entryToRename = entry
        newFileName = entry.fileName
        isShowingRenameAlert = true
    }

    private func performRename(entry: ExcalidrawFileEntry, newName: String) {
        guard !newName.isEmpty, newName != entry.fileName else { return }
        let newFileName = newName.hasSuffix(".excalidraw") ? newName : "\(newName).excalidraw"
        let newURL = entry.fileURL.deletingLastPathComponent().appendingPathComponent(newFileName)
        do {
            try FileManager.default.moveItem(at: entry.fileURL, to: newURL)
            documentManager.folderStore.updateEntryAfterRename(id: entry.id, newFileURL: newURL, newFileName: newFileName)
            // If the renamed file is currently open, reload it with the new docId
            if selectedEntryId == entry.id {
                viewModel.updateDocId(newURL.path)
            }
        } catch {
            // Handle error silently
        }
    }

    @ViewBuilder
    private var sidebarView: some View {
        // Update tree when needed
        let _ = updateFileTreeIfNeeded()
        
        let base = List(selection: folderSelection) {
            // Folders section - Apple Notes style
            Section {
                ForEach(documentManager.sources) { source in
                    Label(source.displayName, systemImage: "folder.fill")
                        .tag(source.id)
                        .font(.body)
                        .contextMenu {
                            Button("Remove") {
                                documentManager.removeFolder(id: source.id)
                            }
                        }
                }
            }
            
            // File tree section
            if let root = fileTreeRoot {
                Section {
                    FileTreeContentView(
                        node: root,
                        selectedEntryId: $selectedEntryId,
                        onSelectFile: { entry in
                            viewModel.open(entry: entry)
                        },
                        onRename: { entry in
                            renameEntry(entry)
                        },
                        onDelete: { entry in
                            deleteEntry(entry)
                        }
                    )
                } header: {
                    Text("Documents")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Folders")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    selectedEntryId = nil
                    viewModel.createNewDocument()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(documentManager.sources.isEmpty)
                .help("New document")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openFolderPicker()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    documentManager.refreshIndexes()
                    // Rebuild tree after refresh
                    if let activeFolderId = documentManager.activeFolderId,
                       let source = documentManager.sources.first(where: { $0.id == activeFolderId }) {
                        fileTreeRoot = FileTreeBuilder.buildTree(
                            entries: filteredEntries,
                            folderName: source.displayName
                        )
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }

        if #available(macOS 14.0, *) {
            base.toolbar(removing: .sidebarToggle)
        } else {
            base
        }
    }
}

final class WebCanvasViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    @Published var statusText: String = "Loading canvas..."
    @Published var isWebViewReady = false
    @Published var isCanvasReady = false
    @Published var styleStatusText: String = "Styles loading..."
    @Published var isStyleReady = false
    @Published var hasUnsavedChanges = false
    let webView: WKWebView

    private let messageHandlerName = "bridge"
    private var didSendInitialScene = false
    private var isBridgeReady = false
    private var didStartLoading = false
    private var readinessCheckAttempts = 0
    private var readinessCheckWorkItem: DispatchWorkItem?
    private let readinessCheckInterval: TimeInterval = 0.5
    private let readinessCheckMaxAttempts = 20
    private var styleCheckAttempts = 0
    private var styleCheckWorkItem: DispatchWorkItem?
    private let styleCheckInterval: TimeInterval = 0.5
    private let styleCheckMaxAttempts = 20
    private let documentManager: DocumentManager
    private let aiModule: AIModule
    private let schemeHandler = BundleSchemeHandler()
    private var pendingScenePayload: [String: Any]?

    init(documentManager: DocumentManager, aiModule: AIModule = EmptyAIModule()) {
        self.documentManager = documentManager
        self.aiModule = aiModule
        let contentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "app")
        config.userContentController = contentController
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        contentController.add(self, name: messageHandlerName)
        webView.navigationDelegate = self
    }

    func prewarm() {
        load()
    }

    func load() {
        guard !didStartLoading else { return }
        didStartLoading = true
        isWebViewReady = false
        isCanvasReady = false
        isStyleReady = false
        readinessCheckAttempts = 0
        readinessCheckWorkItem?.cancel()
        styleCheckAttempts = 0
        styleCheckWorkItem?.cancel()
        statusText = "Loading canvas..."
        styleStatusText = "Styles loading..."
        if Bundle.main.url(forResource: "index", withExtension: "html") != nil,
           let bundleURL = URL(string: "app:///index.html") {
            webView.load(URLRequest(url: bundleURL))
        } else if let devURL = URL(string: "http://localhost:5173") {
            webView.load(URLRequest(url: devURL))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didSendInitialScene else { return }
        didSendInitialScene = true
        isWebViewReady = true
        loadInitialScene()
        scheduleCanvasReadinessCheck()
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
            let dirty = payload["dirty"] as? Bool ?? true
            hasUnsavedChanges = dirty
            statusText = dirty ? "Unsaved changes" : "All changes saved"
        } else if type == "webReady" {
            markCanvasReady()
            isBridgeReady = true
            flushPendingSceneIfNeeded()
        } else if type == "exportResult" {
            handleExport(payload: payload)
        } else if type == "requestAI" {
            handleRequestAI(payload: payload)
        }
    }

    private func markCanvasReady() {
        isCanvasReady = true
        statusText = "Canvas ready"
        readinessCheckWorkItem?.cancel()
        scheduleStyleReadinessCheck()
    }

    private func scheduleCanvasReadinessCheck() {
        readinessCheckWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.checkCanvasReadiness()
        }
        readinessCheckWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + readinessCheckInterval, execute: workItem)
    }

    private func checkCanvasReadiness() {
        guard !isCanvasReady else { return }
        readinessCheckAttempts += 1
        let js = "document.querySelector('canvas') !== null"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self else { return }
            if let ready = result as? Bool, ready {
                self.markCanvasReady()
                return
            }
            if self.readinessCheckAttempts < self.readinessCheckMaxAttempts {
                self.scheduleCanvasReadinessCheck()
            } else {
                self.statusText = "Canvas load timeout"
            }
        }
    }

    private func scheduleStyleReadinessCheck() {
        guard !isStyleReady else { return }
        styleCheckWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.checkStyleReadiness()
        }
        styleCheckWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + styleCheckInterval, execute: workItem)
    }

    private func checkStyleReadiness() {
        guard !isStyleReady else { return }
        styleCheckAttempts += 1
        let js = """
        (() => {
          const cssVar = getComputedStyle(document.documentElement)
            .getPropertyValue('--xexcalidraw-styles-loaded');
          if (cssVar && cssVar.trim().length > 0) {
            return true;
          }
          for (const sheet of Array.from(document.styleSheets)) {
            try {
              for (const rule of Array.from(sheet.cssRules || [])) {
                if (rule.cssText && rule.cssText.includes('--xexcalidraw-styles-loaded')) {
                  return true;
                }
              }
            } catch {
              continue;
            }
          }
          return false;
        })()
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self else { return }
            if let ready = result as? Bool, ready {
                self.isStyleReady = true
                self.styleStatusText = "Styles ready"
                self.styleCheckWorkItem?.cancel()
                return
            }
            if self.styleCheckAttempts < self.styleCheckMaxAttempts {
                self.scheduleStyleReadinessCheck()
            } else {
                self.styleStatusText = "Styles load timeout"
            }
        }
    }

    private func handleExport(payload: [String: Any]) {
        guard
            let format = payload["format"] as? String,
            let dataBase64 = payload["dataBase64"] as? String,
            let exportData = Data(base64Encoded: dataBase64),
            let exportType = exportType(for: format)
        else {
            statusText = "Export failed"
            return
        }

        do {
            let exportDirectory = try resolveExportDirectory()
            let fileName = makeExportFileName(extension: exportType.preferredFilenameExtension ?? format)
            let fileURL = exportDirectory.appendingPathComponent(fileName)
            try exportData.write(to: fileURL, options: [.atomic])
            statusText = "Exported \(fileName)"
            presentSavePanel(data: exportData, suggestedName: fileName, contentType: exportType, initialDirectory: exportDirectory)
        } catch {
            statusText = "Export error: \(error.localizedDescription)"
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
                    self?.queueScenePayload([
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

    private func exportType(for format: String) -> UTType? {
        switch format.lowercased() {
        case "png":
            return .png
        case "svg":
            return .svg
        case "json":
            return .json
        default:
            return nil
        }
    }

    private func presentSavePanel(
        data: Data,
        suggestedName: String,
        contentType: UTType,
        initialDirectory: URL
    ) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [contentType]
            panel.nameFieldStringValue = suggestedName
            panel.directoryURL = initialDirectory
            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try data.write(to: url, options: [.atomic])
                    self?.statusText = "Saved \(url.lastPathComponent)"
                } catch {
                    self?.statusText = "Save error: \(error.localizedDescription)"
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
        let normalizedSceneJson: Any
        if let sceneText = sceneJson as? String,
           let sceneData = sceneText.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: sceneData) {
            normalizedSceneJson = jsonObject
        } else {
            normalizedSceneJson = sceneJson
        }
        guard JSONSerialization.isValidJSONObject(normalizedSceneJson) else {
            statusText = "Save error: Invalid scene JSON"
            return
        }

        documentManager.saveScene(docId: docId, sceneJson: normalizedSceneJson) { [weak self] result in
            switch result {
            case .success(let entry):
                self?.statusText = "Saved \(entry.fileName)"
                self?.hasUnsavedChanges = false
            case .failure(let error):
                self?.statusText = "Save error: \(error.localizedDescription)"
            }
        }
    }

    func createNewDocument() {
        documentManager.createBlankDocument { [weak self] result in
            switch result {
            case .success(let scene):
                self?.queueScenePayload([
                    "docId": scene.docId,
                    "sceneJson": scene.sceneJson,
                    "readOnly": scene.readOnly
                ])
                self?.statusText = "Created new document"
                self?.hasUnsavedChanges = false
            case .failure(let error):
                self?.statusText = "New document error: \(error.localizedDescription)"
            }
        }
    }

    func open(entry: ExcalidrawFileEntry) {
        do {
            let scene = try documentManager.open(entry: entry)
            let payload: [String: Any] = [
                "docId": scene.docId,
                "sceneJson": scene.sceneJson,
                "readOnly": scene.readOnly
            ]
            // If bridge is not ready, queue the payload; otherwise send immediately
            if isBridgeReady {
                send(type: "loadScene", payload: payload)
            } else {
                queueScenePayload(payload)
            }
            statusText = "Loaded \(entry.fileName)"
            hasUnsavedChanges = false
        } catch {
            statusText = "Load error: \(error.localizedDescription)"
        }
    }

    func updateDocId(_ newDocId: String) {
        // Send updateDocId message to WebView to update the current docId without reloading scene
        let payload: [String: Any] = ["docId": newDocId]
        if isBridgeReady {
            send(type: "updateDocId", payload: payload)
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
        queueScenePayload(payload)
        statusText = "Loaded new scene"
        hasUnsavedChanges = false
    }

    func restoreDraft(_ draft: DocumentDraft) {
        queueScenePayload([
            "docId": draft.docId,
            "sceneJson": draft.sceneJson,
            "readOnly": false
        ])
        statusText = "Restored draft"
        hasUnsavedChanges = true
    }

    private func queueScenePayload(_ payload: [String: Any]) {
        pendingScenePayload = payload
        flushPendingSceneIfNeeded()
    }

    private func flushPendingSceneIfNeeded() {
        guard isBridgeReady, let payload = pendingScenePayload else { return }
        pendingScenePayload = nil
        send(type: "loadScene", payload: payload)
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

final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "BundleSchemeHandler", code: 1))
            return
        }
        var resourcePath = ""
        if let host = url.host, !host.isEmpty {
            resourcePath = host
        }
        resourcePath += url.path
        if resourcePath.hasPrefix("/") {
            resourcePath.removeFirst()
        }
        if resourcePath.isEmpty {
            resourcePath = "index.html"
        }
        guard
            let baseURL = Bundle.main.resourceURL,
            let data = try? Data(contentsOf: baseURL.appendingPathComponent(resourcePath))
        else {
            urlSchemeTask.didFailWithError(NSError(domain: "BundleSchemeHandler", code: 2))
            return
        }
        let mimeType = mimeType(for: (resourcePath as NSString).pathExtension)
        let textEncoding: String? = {
            if mimeType.hasPrefix("text/") || mimeType == "application/javascript" || mimeType == "application/json" {
                return "utf-8"
            }
            return nil
        }()
        let response = URLResponse(
            url: url,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: textEncoding
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html":
            return "text/html"
        case "js":
            return "application/javascript"
        case "css":
            return "text/css"
        case "svg":
            return "image/svg+xml"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "json", "map":
            return "application/json"
        case "wasm":
            return "application/wasm"
        case "woff2":
            return "font/woff2"
        case "woff":
            return "font/woff"
        case "ttf":
            return "font/ttf"
        default:
            return "application/octet-stream"
        }
    }
}

struct WebCanvasView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
