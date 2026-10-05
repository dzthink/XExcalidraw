import SwiftUI
import Combine
import AppKit
import ExcalidrawShared
import UniformTypeIdentifiers
import WebKit

@main
struct ExcalidrawMacApp: App {
    @NSApplicationDelegateAdaptor(SiyeApplicationDelegate.self) private var applicationDelegate
    @AppStorage("siye.appearance") private var appearance = AppearancePreference.system.rawValue
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme((AppearancePreference(rawValue: appearance) ?? .system).colorScheme)
        }
        .windowStyle(.automatic)
        Settings { SiyeSettingsView() }
    }
}

private final class CanvasSession: ObservableObject {
    let documentManager: DocumentManager
    let viewModel: WebCanvasViewModel
    private var subscriptions = Set<AnyCancellable>()

    init() {
        let manager: DocumentManager
#if DEBUG
        if ProcessInfo.processInfo.environment["SIYE_UI_TEST_FIXTURE"] == "documents" {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("UITests-" + UUID().uuidString)
            let defaults = UserDefaults(suiteName: "siye.uitests." + UUID().uuidString)!
            let store = FolderSourceStore(userDefaults: defaults, indexStore: ExcalidrawJSONFileIndexStore(fileURL: root.appendingPathComponent("index.json")))
            manager = DocumentManager(store: store, draftDirectory: root.appendingPathComponent("drafts"))
            do {
                let folder = root.appendingPathComponent("Test Documents")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: SiyeDocumentType.excalidraw.blankScene).write(to: folder.appendingPathComponent("Test Canvas.excalidraw"))
                try store.addFolder(url: folder)
            } catch { assertionFailure("UI test fixture failed: \(error)") }
        } else {
            manager = DocumentManager()
        }
#else
        manager = DocumentManager()
#endif
        documentManager = manager
        viewModel = WebCanvasViewModel(documentManager: manager)
        manager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        viewModel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var session = CanvasSession()
    private var documentManager: DocumentManager { session.documentManager }
    private var viewModel: WebCanvasViewModel { session.viewModel }
    @State private var didStartUp = false
    @State private var isShowingDraftAlert = false
    @State private var pendingDraft: DocumentDraft?
    @State private var selectedEntryId: UUID?
    @State private var editingEntryId: UUID?
    @State private var editingFileName: String = ""
    @State private var fileTreeRoots: [FileTreeNode] = []
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var lastExpandedSidebarWidth: CGFloat = SidebarBehavior.defaultWidth


    
    /// 重建所有文件树根节点
    private func rebuildFileTrees() {
        let sources = documentManager.sources
        let entries = documentManager.indexedEntries
        
        var newRoots: [FileTreeNode] = []
        for source in sources {
            let sourceEntries = entries.filter { $0.folderId == source.id }
            let folderPaths = collectRelativeFolderPaths(for: source)
            let root = FileTreeBuilder.buildTree(
                entries: sourceEntries,
                folderName: source.displayName,
                sourceId: source.id,
                folderPaths: folderPaths
            )
            root.isExpanded = true
            newRoots.append(root)
        }
        
        fileTreeRoots = newRoots
    }

    private func collectRelativeFolderPaths(for source: FolderSource) -> [String] {
        guard let rootURL = documentManager.folderStore.resolveURL(for: source) else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else {
            return []
        }

        var paths: [String] = []
        for case let folderURL as URL in enumerator {
            do {
                let values = try folderURL.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
                guard values.isDirectory == true, values.isHidden != true else { continue }
                let relativePath = folderURL.path.replacingOccurrences(of: rootURL.path.appending("/"), with: "")
                if !relativePath.isEmpty {
                    paths.append(relativePath)
                }
            } catch {
                continue
            }
        }
        return paths.sorted()
    }

    private func makeUntitledFileURL(in folderURL: URL, type: SiyeDocumentType) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let baseName = "Untitled-\(timestamp)"
        var candidate = baseName
        var counter = 1
        var fileURL = folderURL.appendingPathComponent("\(candidate)\(type.fileExtension)")
        while FileManager.default.fileExists(atPath: fileURL.path) {
            candidate = "\(baseName)-\(counter)"
            counter += 1
            fileURL = folderURL.appendingPathComponent("\(candidate)\(type.fileExtension)")
        }
        return fileURL
    }

    private func makeUntitledFolderURL(in folderURL: URL) -> URL {
        let baseName = "New Folder"
        var candidate = baseName
        var counter = 2
        var targetURL = folderURL.appendingPathComponent(candidate, isDirectory: true)
        while FileManager.default.fileExists(atPath: targetURL.path) {
            candidate = "\(baseName) \(counter)"
            counter += 1
            targetURL = folderURL.appendingPathComponent(candidate, isDirectory: true)
        }
        return targetURL
    }

    private func resolveFolderContext(for folderNode: FileTreeNode) -> (sourceId: UUID, rootURL: URL, folderURL: URL)? {
        guard let sourceId = folderNode.sourceId,
              let source = documentManager.sources.first(where: { $0.id == sourceId }),
              let rootURL = documentManager.folderStore.resolveURL(for: source) else {
            return nil
        }
        let folderURL: URL
        if folderNode.path.isEmpty {
            folderURL = rootURL
        } else {
            folderURL = rootURL.appendingPathComponent(folderNode.path, isDirectory: true)
        }
        return (sourceId: sourceId, rootURL: rootURL, folderURL: folderURL)
    }

    private func createFile(in folderNode: FileTreeNode, type: SiyeDocumentType) {
        guard let context = resolveFolderContext(for: folderNode) else { return }
        let sceneJson = type.blankScene
        let fileURL = makeUntitledFileURL(in: context.folderURL, type: type)
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: sceneJson, options: [.prettyPrinted])
            try jsonData.write(to: fileURL, options: [.atomic])
            if let entry = documentManager.folderStore.upsertEntry(
                for: fileURL,
                folderId: context.sourceId,
                rootURL: context.rootURL,
                lastOpenedAt: Date()
            ) {
                selectedEntryId = entry.id
                viewModel.open(entry: entry)
            }
            documentManager.refreshIndexes()
        } catch {
            // Keep existing behavior: fail silently in the sidebar action.
        }
    }

    private func createFolder(in folderNode: FileTreeNode) {
        guard let context = resolveFolderContext(for: folderNode) else { return }
        let folderURL = makeUntitledFolderURL(in: context.folderURL)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
            folderNode.isExpanded = true
            documentManager.refreshIndexes()
        } catch {
            // Keep existing behavior: fail silently in the sidebar action.
        }
    }

    private func deleteFolderToTrash(_ folderNode: FileTreeNode) {
        guard let context = resolveFolderContext(for: folderNode) else { return }
        do {
            _ = try FileManager.default.trashItem(at: context.folderURL, resultingItemURL: nil)
            if folderNode.path.isEmpty {
                removeFolderFromSidebar(context.sourceId)
            } else {
                if let selectedEntry = documentManager.indexedEntries.first(where: { $0.id == selectedEntryId }),
                   selectedEntry.fileURL.path.hasPrefix(context.folderURL.path.appending("/")) {
                    selectedEntryId = nil
                }
                documentManager.refreshIndexes()
            }
        } catch {
            // Keep existing behavior: fail silently in the sidebar action.
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            sidebarView
                .navigationSplitViewColumnWidth(min: 40, ideal: lastExpandedSidebarWidth, max: 520)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: SidebarWidthPreferenceKey.self, value: proxy.size.width)
                    }
                )
        } detail: {
            ZStack {
                WebCanvasView(webView: viewModel.webView, accessibilityID: viewModel.isCanvasReady && viewModel.isStyleReady ? "canvas-ready" : "canvas-loading")
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
            .overlay(alignment: .bottomLeading) {
                if viewModel.isDocumentLoading {
                    HStack { ProgressView().controlSize(.small); Text("正在读取文件…") }
                        .padding(10).background(.regularMaterial).cornerRadius(8).padding()
                } else if let error = viewModel.documentLoadError {
                    HStack { Text("文件打开失败：\(error)"); Button("关闭") { viewModel.documentLoadError = nil } }
                        .padding(10).background(.regularMaterial).cornerRadius(8).padding()
                }
            }
            .navigationTitle("")
        }
        .task {
            guard !didStartUp else { return }
            didStartUp = true
            viewModel.prewarm()
            viewModel.load()
        }
        .onAppear {
            // 初次显示时重建文件树
            rebuildFileTrees()
            viewModel.setPreferredTheme(colorScheme)
        }
        .onChange(of: documentManager.indexedEntries.map(\.fileURL)) { _ in
            // 当索引条目变化时重建树
            rebuildFileTrees()
        }
        .onChange(of: documentManager.sources) { _ in
            // 当 sources 变化时重建树
            rebuildFileTrees()
        }
        .onChange(of: colorScheme) { newColorScheme in
            viewModel.setPreferredTheme(newColorScheme)
        }
        .onPreferenceChange(SidebarWidthPreferenceKey.self) { width in
            if !SidebarBehavior.shouldCollapse(width: width) {
                lastExpandedSidebarWidth = width
            } else if splitViewVisibility != .detailOnly {
                splitViewVisibility = .detailOnly
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
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { openImportPicker() } label: { Label("导入", systemImage: "square.and.arrow.down") }
                    .disabled(!documentManager.hasActiveSource)
            }
            ToolbarItem(placement: .automatic) {
                DocumentExportMenu(mindMap: viewModel.editorKind == "mindmap") { viewModel.requestExport(format: $0) }
                    .disabled(documentManager.currentEntry == nil || !viewModel.isCanvasReady)
            }
            ToolbarItem(placement: .principal) {
                DesktopEditorToolbar(viewModel: viewModel)
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        splitViewVisibility = splitViewVisibility == .detailOnly ? .all : .detailOnly
                    }
                } label: {
                    Image(systemName: splitViewVisibility == .detailOnly ? "sidebar.left" : "sidebar.leading")
                }
                .accessibilityIdentifier("sidebar-toggle-button")
                .accessibilityLabel(splitViewVisibility == .detailOnly ? "Show navigation" : "Collapse navigation")
                .help(splitViewVisibility == .detailOnly ? "Show navigation" : "Collapse navigation")
            }
        }
    }

    private func openImportPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentTransferFormats.importTypes
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            viewModel.flushEditing { success in
                guard success else { if scoped { url.stopAccessingSecurityScopedResource() }; return }
                documentManager.importScene(from: url) { result in
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    switch result {
                    case .success(let entry): selectedEntryId = entry.id; viewModel.open(entry: entry)
                    case .failure(let error): viewModel.documentLoadError = "导入失败：" + error.localizedDescription
                    }
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
                try documentManager.addFolder(url: url)
            } catch {
                // Handle errors in the caller if needed.
            }
        }
    }
    
    /// 从侧边栏移除文件夹
    private func removeFolderFromSidebar(_ folderId: UUID) {
        documentManager.removeFolder(id: folderId)
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
        editingEntryId = entry.id
        editingFileName = ExcalidrawFileName.displayName(from: entry.fileName)
    }

    private func performRename(entry: ExcalidrawFileEntry, newName: String) {
        guard !newName.isEmpty, newName != entry.fileName else { return }
        documentManager.renameEntry(entry, to: newName) { result in
            if case .success(let renamed) = result, selectedEntryId == entry.id {
                viewModel.updateDocId(renamed.fileURL.path)
            }
        }
    }

    @ViewBuilder
    private var sidebarView: some View {
        let base = ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if fileTreeRoots.isEmpty {
                    // 没有文件夹时的提示
                    Section {
                        VStack(alignment: .center, spacing: 12) {
                            Image(systemName: "externaldrive.badge.plus")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("Add a folder to start")
                                .foregroundStyle(.secondary)
                            Button("Add Folder") {
                                openFolderPicker()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                } else {
                    // 显示所有根目录平铺
                    ForEach(fileTreeRoots) { root in
                        FolderRowView(
                            node: root,
                            level: 0,
                            editingEntryId: $editingEntryId,
                            editingFileName: $editingFileName,
                            onCreateFile: { _, type in
                                createFile(in: root, type: type)
                            },
                            onCreateFolder: { _ in
                                createFolder(in: root)
                            },
                            onDeleteFolder: { _ in
                                deleteFolderToTrash(root)
                            },
                            onRemove: {
                                if let sourceId = root.sourceId {
                                    removeFolderFromSidebar(sourceId)
                                }
                            }
                        )
                        FileTreeContentView(
                            node: root,
                            selectedEntryId: $selectedEntryId,
                            editingEntryId: $editingEntryId,
                            editingFileName: $editingFileName,
                            onSelectFile: { entry in
                                viewModel.open(entry: entry)
                            },
                            onRename: { entry in
                                renameEntry(entry)
                            },
                            onCommitRename: { entry, newName in
                                performRename(entry: entry, newName: newName)
                                editingEntryId = nil
                                editingFileName = ""
                            },
                            onCancelRename: {
                                editingEntryId = nil
                                editingFileName = ""
                            },
                            onDelete: { entry in
                                deleteEntry(entry)
                            },
                            onCreateFile: { node, type in
                                createFile(in: node, type: type)
                            },
                            onCreateFolder: { node in
                                createFolder(in: node)
                            },
                            onDeleteFolder: { node in
                                deleteFolderToTrash(node)
                            }
                        )
                    }
                }
            }
            .padding(8)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .accessibilityIdentifier("documents-sidebar")
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openFolderPicker()
                } label: {
                    Image(systemName: "externaldrive.badge.plus")
                }
                .help("Mount folder")
            }
        }

        if #available(macOS 14.0, *) {
            base.toolbar(removing: .sidebarToggle)
        } else {
            base
        }
    }
}

private struct SidebarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = SidebarBehavior.defaultWidth

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum ExcalidrawFileName {
    static func displayName(from fileName: String) -> String {
        SiyeDocumentType.displayName(from: fileName)
    }

    static func normalizedFileName(from input: String, originalFileName: String) -> String {
        let suffix = originalFileName.lowercased().hasSuffix(".excalidraw.json") ? ".excalidraw.json" : (SiyeDocumentType(fileName: originalFileName)?.fileExtension ?? ".excalidraw")
        return SiyeDocumentType.displayName(from: input) + suffix
    }
}

enum SidebarBehavior {
    static let defaultWidth: CGFloat = 240
    static let collapseThreshold: CGFloat = 50

    static func shouldCollapse(width: CGFloat) -> Bool {
        width < collapseThreshold
    }
}

// MARK: - WebCanvasViewModel

final class WebCanvasViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    @Published var statusText: String = "Loading canvas..."
    @Published var isDocumentLoading = false
    @Published var documentLoadError: String?
    @Published var isWebViewReady = false
    @Published var isCanvasReady = false
    @Published var styleStatusText: String = "Styles loading..."
    @Published var isStyleReady = false
    @Published var hasUnsavedChanges = false
    @Published var editorKind = "drawing"
    @Published var editorViewMode = "outline"
    @Published var activeDrawingTool = "selection"
    @Published var drawingToolLocked = false
    @Published var editorReadOnly = false
    let webView: WKWebView

    func requestExport(format: String) {
        flushEditing { [weak self] success in
            if success { self?.send(type: "requestExport", payload: ["format": format, "embedScene": true]) }
        }
    }

    func performToolbarAction(_ action: String, value: String? = nil) {
        var payload: [String: Any] = ["action": action]
        if let value { payload["value"] = value }
        webView.window?.makeFirstResponder(webView)
        send(type: "desktopToolbarAction", payload: payload)
    }

    private var currentDocumentID: String?
    private var sceneGeneration = 0
    private let bridgeQueue = DispatchQueue(label: "com.xexcalidraw.bridge", qos: .userInitiated)
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
    private let schemeHandler = BundleResourceSchemeHandler()
    private var pendingScenePayload: [String: Any]?
    private var preferredTheme: String = "light"
    private let aiEnabledKey = "aiEnabled"

    private var isAIEnabled: Bool {
        if UserDefaults.standard.object(forKey: aiEnabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: aiEnabledKey)
    }

    init(documentManager: DocumentManager, aiModule: AIModule = EmptyAIModule()) {
        self.documentManager = documentManager
        self.aiModule = aiModule
        let contentController = WKUserContentController()
        self.preferredTheme = Self.currentSystemTheme()
        let bootstrapScript = Self.makeThemeBootstrapScript(theme: preferredTheme)
        let userScript = WKUserScript(
            source: bootstrapScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(userScript)
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "app")
        config.userContentController = contentController
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        contentController.add(WeakScriptMessageHandler(self), name: messageHandlerName)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        SiyeApplicationDelegate.canvases.add(self)
    }

    deinit {
        readinessCheckWorkItem?.cancel()
        styleCheckWorkItem?.cancel()
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        if currentDocumentID?.lowercased().hasSuffix(".mindmap") == true { panel.allowedContentTypes = [.png, .jpeg, .gif, .webP] }
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.begin { result in completionHandler(result == .OK ? panel.urls : nil) }
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
        bridgeQueue.async { [weak self] in
            guard let data = payloadString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String,
                  let payload = json["payload"] as? [String: Any] else { return }
            DispatchQueue.main.async { self?.handleMessage(type: type, payload: payload) }
        }
    }

    private func handleMessage(type: String, payload: [String: Any]) {
        if type == "desktopToolbarState" {
            guard (payload["docId"] as? String ?? "") == (currentDocumentID ?? "") else { return }
            editorKind = payload["kind"] as? String ?? "drawing"
            editorViewMode = payload["viewMode"] as? String ?? "outline"
            activeDrawingTool = payload["activeTool"] as? String ?? "selection"
            drawingToolLocked = payload["locked"] as? Bool ?? false
            editorReadOnly = payload["readOnly"] as? Bool ?? false
        } else if type == "saveScene" {
            handleSave(payload: payload)
        } else if type == "openLink" {
            if let value = payload["url"] as? String, let url = URL(string: value), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
        } else if type == "saveAttachment" {
            handleSaveAttachment(payload: payload)
        } else if type == "didChange" {
            guard payload["docId"] as? String == currentDocumentID else { return }
            let dirty = payload["dirty"] as? Bool ?? true
            if hasUnsavedChanges != dirty {
                hasUnsavedChanges = dirty
                statusText = dirty ? "Unsaved changes" : "All changes saved"
            }
        } else if type == "webReady" {
            markCanvasReady()
            isBridgeReady = true
            flushPendingSceneIfNeeded()
            sendThemeUpdate()
            sendAIConfig()
            // Re-apply theme after first paint to avoid initial flash on cold starts.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.sendThemeUpdate()
            }
        } else if type == "exportFailed" {
            documentLoadError = "导出失败：" + (payload["error"] as? String ?? "未知错误")
        } else if type == "exportResult" {
            handleExport(payload: payload)
        } else if type == "requestAI" {
            handleRequestAI(payload: payload)
        } else if type == "cursorChanged" {
            handleCursorChanged(payload: payload)
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
            let fileName = makeExportFileName(extension: format)
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

    private func handleCursorChanged(payload: [String: Any]) {
        guard let cursor = payload["cursor"] as? String else { return }
        DispatchQueue.main.async {
            Self.setSystemCursor(cursor)
        }
    }

    private static func setSystemCursor(_ cursor: String) {
        let cursorMap: [String: NSCursor] = [
            "default": .arrow,
            "auto": .arrow,
            "pointer": .pointingHand,
            "text": .iBeam,
            "crosshair": .crosshair,
            "move": .openHand,
            "grab": .openHand,
            "grabbing": .closedHand,
            "ew-resize": .resizeLeftRight,
            "ns-resize": .resizeUpDown,
            "nesw-resize": .arrow, // Fallback
            "nwse-resize": .arrow, // Fallback
            "col-resize": .resizeLeftRight,
            "row-resize": .resizeUpDown,
            "not-allowed": .operationNotAllowed,
            "wait": .arrow, // No wait cursor in NSCursor
            "help": .arrow, // No help cursor in NSCursor
            "zoom-in": .arrow, // No zoom-in cursor in NSCursor
            "zoom-out": .arrow, // No zoom-out cursor in NSCursor
            "none": .arrow // Use arrow as fallback for hidden cursor
        ]

        if let nsCursor = cursorMap[cursor] {
            if nsCursor != NSCursor.current {
                nsCursor.set()
            }
        } else {
            // Default to arrow for unknown cursor types
            if NSCursor.current != .arrow {
                NSCursor.arrow.set()
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
            .lastPathComponent ?? "Siye"
        return "\(baseName)-\(timestamp).\(fileExtension)"
    }

    private func exportType(for format: String) -> UTType? {
        DocumentTransferFormats.exportType(format)
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
        let requestId = payload["requestId"] as? String ?? ""
        guard let docId = payload["docId"] as? String, let raw = payload["sceneJson"] else {
            send(type: "saveResult", payload: ["requestId": requestId, "success": false, "error": "保存数据不完整"])
            return
        }
        documentManager.saveScene(docId: docId, sceneJson: raw) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.send(type: "saveResult", payload: ["requestId": requestId, "docId": docId, "success": true])
                case .failure(let error):
                    self.send(type: "saveResult", payload: ["requestId": requestId, "docId": docId, "success": false, "error": error.localizedDescription])
                }
            }
        }
    }

    func flushEditing(completion: @escaping (Bool) -> Void) {
        guard isBridgeReady else { completion(true); return }
        webView.callAsyncJavaScript("return window.siyeFlush ? await window.siyeFlush() : true", arguments: [:], in: nil, in: .page) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let value): completion(value as? Bool ?? false)
                case .failure: completion(false)
                }
            }
        }
    }

    private func handleSaveAttachment(payload: [String: Any]) {
        guard let requestId = payload["requestId"] as? String,
              let docId = payload["docId"] as? String else { return }
        guard let mimeType = payload["mimeType"] as? String,
              let encoded = payload["dataBase64"] as? String,
              encoded.utf8.count <= 14 * 1024 * 1024,
              let context = documentManager.attachmentContext(docId: docId) else {
            send(type: "attachmentSaveFailed", payload: ["requestId": requestId, "error": "无法保存图片附件"])
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                guard let imageData = Data(base64Encoded: encoded), imageData.count <= 10 * 1024 * 1024 else { throw MindMapAttachmentError.unsupportedImage }
                let relativePath = try MindMapAttachmentStore.save(
                    imageData: imageData,
                    mimeType: mimeType,
                    documentURL: context.documentURL,
                    repositoryURL: context.repositoryURL
                )
                DispatchQueue.main.async {
                    self?.send(type: "attachmentSaved", payload: ["requestId": requestId, "relativePath": relativePath])
                }
            } catch {
                DispatchQueue.main.async {
                    self?.send(type: "attachmentSaveFailed", payload: ["requestId": requestId, "error": error.localizedDescription])
                }
            }
        }
    }

    func createNewDocument(in folderId: UUID? = nil) {
        documentManager.createBlankDocument(in: folderId) { [weak self] result in
            switch result {
            case .success(let scene):
                self?.queueScenePayload([
                    "docId": scene.docId,
                    "sceneJson": scene.sceneJson,
                    "readOnly": scene.readOnly
                ])
                self?.statusText = "Created new document"
                self?.hasUnsavedChanges = false
                self?.sendThemeUpdate()
            case .failure(let error):
                self?.statusText = "New document error: \(error.localizedDescription)"
            }
        }
    }

    func open(entry: ExcalidrawFileEntry) {
        sceneGeneration += 1
        let generation = sceneGeneration
        statusText = "Loading \(entry.fileName)…"
        isDocumentLoading = true
        documentLoadError = nil
        flushEditing { [weak self] success in
            guard let self, self.sceneGeneration == generation else { return }
            guard success else { self.isDocumentLoading = false; self.documentLoadError = "当前文档未能保存，请稍后重试"; return }
            self.documentManager.read(entry: entry) { [weak self] result in
                guard let self, self.sceneGeneration == generation else { return }
                self.isDocumentLoading = false
                switch result {
                case .success(let scene):
                    self.documentManager.activate(entry: entry)
                    let payload: [String: Any] = ["docId": scene.docId, "sceneJson": scene.sceneJson, "readOnly": scene.readOnly]
                    if self.isBridgeReady { self.deliver(type: "loadScene", payload: payload) }
                    else { self.queueScenePayload(payload) }
                    self.statusText = "Loaded \(entry.fileName)"
                    self.hasUnsavedChanges = false
                    self.sendThemeUpdate()
                case .failure(let error):
                    self.statusText = "Load error: \(error.localizedDescription)"
                    self.documentLoadError = error.localizedDescription
                }
            }
        }
    }

    func updateDocId(_ newDocId: String) {
        pendingScenePayload?["docId"] = newDocId
        // Send updateDocId message to WebView to update the current docId without reloading scene
        let payload: [String: Any] = ["docId": newDocId]
        if isBridgeReady {
            send(type: "updateDocId", payload: payload)
        }
    }

    private func loadInitialScene() {
        guard !isDocumentLoading, pendingScenePayload == nil, currentDocumentID == nil else { return }
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
        sendThemeUpdate()
    }

    func setPreferredTheme(_ colorScheme: ColorScheme) {
        preferredTheme = colorScheme == .dark ? "dark" : "light"
        sendThemeUpdate()
    }

    private func queueScenePayload(_ payload: [String: Any]) {
        pendingScenePayload = payload
        flushPendingSceneIfNeeded()
    }

    private func flushPendingSceneIfNeeded() {
        guard isBridgeReady, let payload = pendingScenePayload else { return }
        pendingScenePayload = nil
        send(type: "loadScene", payload: payload)
        sendThemeUpdate()
    }

    private func sendThemeUpdate() {
        guard isBridgeReady else { return }
        send(type: "setAppState", payload: [
            "theme": preferredTheme
        ])
    }

    private func sendAIConfig() {
        guard isBridgeReady else { return }
        send(type: "aiConfig", payload: [
            "enabled": isAIEnabled
        ])
    }

    private static func currentSystemTheme() -> String {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? "dark" : "light"
    }

    static func makeThemeBootstrapScript(theme: String) -> String {
        let backgroundColor = theme == "dark" ? "#1e1e1e" : "#ffffff"
        let colorScheme = theme == "dark" ? "dark" : "light"
        return """
        (() => {
          window.__XEXCALIDRAW_THEME = "\(theme)";
          const html = document.documentElement;
          html.dataset.nativeDesktop = "true";
          html.style.colorScheme = "\(colorScheme)";
          html.style.backgroundColor = "\(backgroundColor)";
          const applyBody = () => {
            if (document.body) {
              document.body.style.backgroundColor = "\(backgroundColor)";
            }
          };
          if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", applyBody, { once: true });
          } else {
            applyBody();
          }
        })();
        """
    }

    private func send(type: String, payload: [String: Any]) {
        if type == "loadScene", let docId = payload["docId"] as? String {
            let reloadingCurrentDocument = docId == currentDocumentID
            sceneGeneration += 1
            let generation = sceneGeneration
            guard currentDocumentID != nil else { deliver(type: type, payload: payload); return }
            flushEditing { [weak self] success in
                guard let self, success, self.sceneGeneration == generation else { return }
                var latestPayload = payload
                if let entry = self.documentManager.indexedEntries.first(where: { $0.fileURL.path == docId }) {
                    if reloadingCurrentDocument {
                        self.documentManager.read(entry: entry) { [weak self] result in
                            guard let self, self.sceneGeneration == generation else { return }
                            guard case .success(let scene) = result else { return }
                            latestPayload["sceneJson"] = scene.sceneJson
                            self.documentManager.activate(entry: entry)
                            self.deliver(type: type, payload: latestPayload)
                        }
                        return
                    }
                    self.documentManager.activate(entry: entry)
                }
                self.deliver(type: type, payload: latestPayload)
            }
            return
        }
        deliver(type: type, payload: payload)
    }

    private func deliver(type: String, payload: [String: Any]) {
        if (type == "loadScene" || type == "updateDocId"), let docId = payload["docId"] as? String {
            currentDocumentID = docId
            let context = documentManager.attachmentContext(docId: docId)
            schemeHandler.setAttachmentContext(documentURL: context?.documentURL, repositoryURL: context?.repositoryURL)
        }
        bridgeQueue.async { [weak self] in
            let envelope: [String: Any] = ["version": "1.0", "type": type, "payload": payload]
            guard let data = try? JSONSerialization.data(withJSONObject: envelope),
                  let jsonString = String(data: data, encoding: .utf8) else { return }
            let js = "window.bridgeDispatch && window.bridgeDispatch(\(jsonString.debugDescription))"
            DispatchQueue.main.async { self?.webView.evaluateJavaScript(js, completionHandler: nil) }
        }
    }
}


struct WebCanvasView: NSViewRepresentable {
    let webView: WKWebView
    var accessibilityID: String? = nil

    func makeNSView(context: Context) -> NSView {
        // Wrap WKWebView in a custom NSView to ensure proper cursor handling
        let container = WebViewContainer()
        container.addWebView(webView)
        webView.setAccessibilityIdentifier(accessibilityID)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        webView.setAccessibilityIdentifier(accessibilityID)
        // Ensure the web view fills the container
        if let container = nsView as? WebViewContainer {
            container.layoutWebView()
        }
    }
}

/// A container view that properly handles WKWebView's cursor updates in SwiftUI
final class WebViewContainer: NSView {
    private weak var webView: WKWebView?
    private var closeDelegate: SiyeWindowDelegate?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.titleVisibility = .hidden
        if let window, !(window.delegate is SiyeWindowDelegate), let model = webView?.navigationDelegate as? WebCanvasViewModel {
            let delegate = SiyeWindowDelegate(model: model, original: window.delegate)
            closeDelegate = delegate
            window.delegate = delegate
        }
    }

    func addWebView(_ webView: WKWebView) {
        self.webView = webView
        // Use autoresizingMask for layout
        webView.translatesAutoresizingMaskIntoConstraints = true
        // Enable magnification - this can help with cursor updates
        webView.allowsMagnification = true
        addSubview(webView)
        layoutWebView()
    }

    func layoutWebView() {
        guard let webView = webView else { return }
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        layoutWebView()
    }
}

// Flush the editor before AppKit destroys its web view.
final class SiyeWindowDelegate: NSObject, NSWindowDelegate {
    weak var model: WebCanvasViewModel?
    weak var original: NSWindowDelegate?
    private var closing = false
    private var waiting = false
    init(model: WebCanvasViewModel, original: NSWindowDelegate?) { self.model = model; self.original = original }
    override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || (original?.responds(to: selector) ?? false) }
    override func forwardingTarget(for selector: Selector!) -> Any? { original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector) }
    func windowDidBecomeMain(_ notification: Notification) {
        if let model { SiyeApplicationDelegate.canvases.add(model) }
        original?.windowDidBecomeMain?(notification)
    }
    func windowWillClose(_ notification: Notification) {
        if let model { SiyeApplicationDelegate.canvases.remove(model) }
        original?.windowWillClose?(notification)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closing { return original?.windowShouldClose?(sender) ?? true }
        guard !waiting, let model else { return false }
        waiting = true
        model.flushEditing { [weak self, weak sender] success in
            guard let self else { return }
            self.waiting = false
            if success { self.closing = true; sender?.performClose(nil); self.closing = false }
        }
        return false
    }
}

final class SiyeApplicationDelegate: NSObject, NSApplicationDelegate {
    static let canvases = NSHashTable<WebCanvasViewModel>.weakObjects()
    private var terminating = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        let models = Self.canvases.allObjects
        guard !models.isEmpty else { return .terminateNow }
        var remaining = models.count
        var saved = true
        for model in models {
            model.flushEditing { [weak self] success in
                saved = saved && success; remaining -= 1
                if remaining == 0 { self?.terminating = false; sender.reply(toApplicationShouldTerminate: saved) }
            }
        }
        return .terminateLater
    }
}


private struct DesktopEditorToolbar: View {
    @ObservedObject var viewModel: WebCanvasViewModel

    private let tools: [(type: String, symbol: String, label: String)] = [
        ("hand", "hand.draw", "Hand"),
        ("selection", "cursorarrow", "Selection"),
        ("rectangle", "rectangle", "Rectangle"),
        ("diamond", "diamond", "Diamond"),
        ("ellipse", "circle", "Ellipse"),
        ("arrow", "arrow.up.right", "Arrow"),
        ("line", "line.diagonal", "Line"),
        ("freedraw", "pencil.tip", "Draw"),
        ("text", "textformat", "Text"),
        ("image", "photo", "Insert image"),
        ("eraser", "eraser", "Eraser")
    ]

    var body: some View {
        if viewModel.editorKind == "mindmap" {
            Picker("文档视图", selection: Binding(
                get: { viewModel.editorViewMode },
                set: { viewModel.performToolbarAction("view", value: $0) }
            )) {
                Text("大纲").tag("outline")
                Text("思维导图").tag("map")
            }
            .pickerStyle(.segmented)
            .frame(width: 168)
            .accessibilityIdentifier("document-view-switcher")
        } else if !viewModel.editorReadOnly {
            HStack(spacing: 2) {
                toolButton("lock", symbol: viewModel.drawingToolLocked ? "lock.fill" : "lock.open", label: "Keep selected tool active", selected: viewModel.drawingToolLocked)
                Divider().frame(height: 20).padding(.horizontal, 3)
                ForEach(tools, id: \.type) { tool in
                    toolButton("tool", value: tool.type, symbol: tool.symbol, label: tool.label, selected: viewModel.activeDrawingTool == tool.type)
                }
                Menu {
                    Button("Frame") { viewModel.performToolbarAction("tool", value: "frame") }
                    Button("Embed") { viewModel.performToolbarAction("tool", value: "embeddable") }
                    Button("Laser pointer") { viewModel.performToolbarAction("tool", value: "laser") }
                    Divider()
                    Button("Library") { viewModel.performToolbarAction("library") }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 28)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("More tools")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Drawing tools")
        } else {
            Button("Library") { viewModel.performToolbarAction("library") }
        }
    }

    private func toolButton(_ action: String, value: String? = nil, symbol: String, label: String, selected: Bool) -> some View {
        Button {
            viewModel.performToolbarAction(action, value: value)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityValue(selected ? "Selected" : "")
        .help(label)
    }
}
