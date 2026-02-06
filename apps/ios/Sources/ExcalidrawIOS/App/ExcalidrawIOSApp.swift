#if os(iOS)
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
            fileBrowserView
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        selectedEntryId = nil
                        viewModel.createNewDocument()
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                    .disabled(documentManager.sources.isEmpty)
                }
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
            ZStack {
                WebCanvasView(webView: viewModel.webView)
                    .ignoresSafeArea()
                if !viewModel.isCanvasReady {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading canvas…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
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

    private func deleteSources(at offsets: IndexSet) {
        let removedIds = offsets.map { documentManager.sources[$0].id }
        for index in offsets {
            let source = documentManager.sources[index]
            documentManager.removeFolder(id: source.id)
        }
        if let activeId = documentManager.activeFolderId, removedIds.contains(activeId) {
            documentManager.activeFolderId = documentManager.sources.first(where: { !removedIds.contains($0.id) })?.id
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

    private var filteredEntries: [ExcalidrawFileEntry] {
        guard let activeFolderId = documentManager.activeFolderId else { return [] }
        let entries = documentManager.indexedEntries.filter { $0.folderId == activeFolderId }
        // Sort alphabetically by file name
        return entries.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    @ViewBuilder
    private var fileBrowserView: some View {
        // Update tree when needed
        let _ = updateFileTreeIfNeeded()
        
        NavigationStack {
            SidebarView(
                sources: documentManager.sources,
                activeFolderId: $documentManager.activeFolderId,
                selectedEntryId: $selectedEntryId,
                fileTreeRoot: fileTreeRoot,
                onSelectFile: { entry in
                    viewModel.open(entry: entry)
                },
                onRename: { entry in
                    renameEntry(entry)
                },
                onDelete: { entry in
                    deleteEntry(entry)
                },
                onRemoveFolder: { id in
                    documentManager.removeFolder(id: id)
                },
                onRefresh: {
                    documentManager.refreshIndexes()
                    // Rebuild tree after refresh
                    if let activeFolderId = documentManager.activeFolderId,
                       let source = documentManager.sources.first(where: { $0.id == activeFolderId }) {
                        fileTreeRoot = FileTreeBuilder.buildTree(
                            entries: filteredEntries,
                            folderName: source.displayName
                        )
                    }
                }
            )
            .navigationTitle("Folders")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        selectedEntryId = nil
                        viewModel.createNewDocument()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(documentManager.sources.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingPicker = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingPicker) {
                FolderSourcePicker(store: documentManager.folderStore)
            }
        }
    }
}

// Apple Notes style sidebar
struct SidebarView: View {
    let sources: [FolderSource]
    @Binding var activeFolderId: UUID?
    @Binding var selectedEntryId: UUID?
    let fileTreeRoot: FileTreeNode?
    let onSelectFile: (ExcalidrawFileEntry) -> Void
    let onRename: (ExcalidrawFileEntry) -> Void
    let onDelete: (ExcalidrawFileEntry) -> Void
    let onRemoveFolder: (UUID) -> Void
    let onRefresh: () -> Void
    
    var body: some View {
        List {
            // All Folders section - Apple Notes style
            Section {
                ForEach(sources) { source in
                    NavigationLink(value: source.id) {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.orange)
                                .font(.title3)
                            Text(source.displayName)
                                .font(.body)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            onRemoveFolder(source.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            
            // File list section
            if let root = fileTreeRoot {
                Section {
                    FileTreeContentView(
                        node: root,
                        selectedEntryId: $selectedEntryId,
                        onSelectFile: onSelectFile,
                        onRename: onRename,
                        onDelete: onDelete
                    )
                } header: {
                    Text("Documents")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .refreshable {
            onRefresh()
        }
        .navigationDestination(for: UUID.self) { folderId in
            // Navigate to folder content
            FolderContentView(
                folderId: folderId,
                sources: sources,
                selectedEntryId: $selectedEntryId,
                fileTreeRoot: fileTreeRoot,
                onSelectFile: onSelectFile,
                onRename: onRename,
                onDelete: onDelete
            )
        }
    }
}

struct FolderContentView: View {
    let folderId: UUID
    let sources: [FolderSource]
    @Binding var selectedEntryId: UUID?
    let fileTreeRoot: FileTreeNode?
    let onSelectFile: (ExcalidrawFileEntry) -> Void
    let onRename: (ExcalidrawFileEntry) -> Void
    let onDelete: (ExcalidrawFileEntry) -> Void
    
    var folderName: String {
        sources.first { $0.id == folderId }?.displayName ?? "Folder"
    }
    
    var body: some View {
        List {
            if let root = fileTreeRoot {
                FileTreeContentView(
                    node: root,
                    selectedEntryId: $selectedEntryId,
                    onSelectFile: onSelectFile,
                    onRename: onRename,
                    onDelete: onDelete
                )
            } else {
                ContentUnavailableView("No Documents", systemImage: "doc.text.magnifyingglass")
            }
        }
        .navigationTitle(folderName)
    }
}

struct FileTreeContentView: View {
    @ObservedObject var node: FileTreeNode
    @Binding var selectedEntryId: UUID?
    let onSelectFile: (ExcalidrawFileEntry) -> Void
    let onRename: (ExcalidrawFileEntry) -> Void
    let onDelete: (ExcalidrawFileEntry) -> Void
    
    var body: some View {
        ForEach(node.children) { child in
            if child.isFolder {
                FolderNodeView(
                    node: child,
                    selectedEntryId: $selectedEntryId,
                    onSelectFile: onSelectFile,
                    onRename: onRename,
                    onDelete: onDelete,
                    level: 0
                )
            } else if let entry = child.fileEntry {
                FileNodeView(
                    entry: entry,
                    isSelected: selectedEntryId == entry.id,
                    onSelect: {
                        selectedEntryId = entry.id
                        onSelectFile(entry)
                    },
                    onRename: { onRename(entry) },
                    onDelete: { onDelete(entry) },
                    level: 0
                )
            }
        }
    }
}

struct FolderNodeView: View {
    @ObservedObject var node: FileTreeNode
    @Binding var selectedEntryId: UUID?
    let onSelectFile: (ExcalidrawFileEntry) -> Void
    let onRename: (ExcalidrawFileEntry) -> Void
    let onDelete: (ExcalidrawFileEntry) -> Void
    let level: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Folder header with expand/collapse button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    node.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.orange)
                        .font(.body)
                    Text(node.name)
                        .font(.body)
                    Spacer()
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
                .padding(.leading, CGFloat(level * 16))
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            
            // Children
            if node.isExpanded {
                ForEach(node.children) { child in
                    if child.isFolder {
                        FolderNodeView(
                            node: child,
                            selectedEntryId: $selectedEntryId,
                            onSelectFile: onSelectFile,
                            onRename: onRename,
                            onDelete: onDelete,
                            level: level + 1
                        )
                    } else if let entry = child.fileEntry {
                        FileNodeView(
                            entry: entry,
                            isSelected: selectedEntryId == entry.id,
                            onSelect: {
                                selectedEntryId = entry.id
                                onSelectFile(entry)
                            },
                            onRename: { onRename(entry) },
                            onDelete: { onDelete(entry) },
                            level: level + 1
                        )
                    }
                }
            }
        }
    }
}

struct FileNodeView: View {
    let entry: ExcalidrawFileEntry
    let isSelected: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let level: Int
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .foregroundStyle(Color.accentColor)
                    .font(.body)
                Text(entry.fileName)
                    .font(.body)
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
            .padding(.leading, CGFloat(level * 16 + 20))
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .contextMenu {
            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
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

struct WebCanvasView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#else
import SwiftUI

@main
struct ExcalidrawIOSApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Excalidraw iOS target is only available on iOS.")
                .padding()
        }
    }
}
#endif
