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
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var documentManager: DocumentManager
    @StateObject private var viewModel: WebCanvasViewModel
    @State private var didStartUp = false
    @State private var isShowingDraftAlert = false
    @State private var pendingDraft: DocumentDraft?
    @State private var selectedEntryId: UUID?
    @State private var editingEntryId: UUID?
    @State private var editingFileName: String = ""
    @State private var fileTreeRoots: [FileTreeNode] = []
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var lastExpandedSidebarWidth: CGFloat = 280

    init() {
        let documentManager = DocumentManager()
        let viewModel = WebCanvasViewModel(documentManager: documentManager)
        viewModel.prewarm()
        _documentManager = StateObject(wrappedValue: documentManager)
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
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

    private func makeUntitledFileURL(in folderURL: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let baseName = "Untitled-\(timestamp)"
        var candidate = baseName
        var counter = 1
        var fileURL = folderURL.appendingPathComponent("\(candidate).excalidraw")
        while FileManager.default.fileExists(atPath: fileURL.path) {
            candidate = "\(baseName)-\(counter)"
            counter += 1
            fileURL = folderURL.appendingPathComponent("\(candidate).excalidraw")
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

    private func createFile(in folderNode: FileTreeNode) {
        guard let context = resolveFolderContext(for: folderNode) else { return }
        let sceneJson: [String: Any] = [
            "elements": [],
            "appState": [:]
        ]
        let fileURL = makeUntitledFileURL(in: context.folderURL)
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
        }
        .onAppear {
            // 初次显示时重建文件树
            rebuildFileTrees()
            viewModel.setPreferredTheme(colorScheme)
        }
        .onChange(of: documentManager.indexedEntries) { _ in
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
        let newFileName = ExcalidrawFileName.normalizedFileName(from: newName)
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
        let base = List {
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
                    RootFolderHeader(
                        node: root,
                        onCreateFile: {
                            createFile(in: root)
                        },
                        onCreateFolder: {
                            createFolder(in: root)
                        },
                        onDeleteFolder: {
                            deleteFolderToTrash(root)
                        },
                        onRemove: {
                            if let sourceId = root.sourceId {
                                removeFolderFromSidebar(sourceId)
                            }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
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
                        onCreateFile: { node in
                            createFile(in: node)
                        },
                        onCreateFolder: { node in
                            createFolder(in: node)
                        },
                        onDeleteFolder: { node in
                            deleteFolderToTrash(node)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.sidebar)
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
    static var defaultValue: CGFloat = 280

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum ExcalidrawFileName {
    static let fileExtension = ".excalidraw"

    static func displayName(from fileName: String) -> String {
        if fileName.hasSuffix(fileExtension) {
            return String(fileName.dropLast(fileExtension.count))
        }
        return fileName
    }

    static func normalizedFileName(from input: String) -> String {
        input.hasSuffix(fileExtension) ? input : "\(input)\(fileExtension)"
    }
}

enum SidebarBehavior {
    static let collapseThreshold: CGFloat = 50

    static func shouldCollapse(width: CGFloat) -> Bool {
        width < collapseThreshold
    }
}

/// 根目录文件夹标题视图
struct RootFolderHeader: View {
    @ObservedObject var node: FileTreeNode
    var onCreateFile: () -> Void
    var onCreateFolder: () -> Void
    var onDeleteFolder: () -> Void
    var onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    node.isExpanded.toggle()
                }
            } label: {
                Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 28)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    node.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "externaldrive.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                    
                    Text(node.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 1)
        .contextMenu {
            Button {
                onCreateFile()
            } label: {
                Label("Create File", systemImage: "doc.badge.plus")
            }

            Button {
                onCreateFolder()
            } label: {
                Label("Create Folder", systemImage: "folder.badge.plus")
            }

            Divider()

            Button(role: .destructive) {
                onDeleteFolder()
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }

            Divider()

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    node.isExpanded.toggle()
                }
            } label: {
                Label(node.isExpanded ? "Collapse" : "Expand", systemImage: node.isExpanded ? "chevron.up" : "chevron.down")
            }

            Button {
                onRemove()
            } label: {
                Label("Remove from Sidebar", systemImage: "minus.circle")
            }
        }
    }
}

// MARK: - WebCanvasViewModel

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
    private var preferredTheme: String = "light"

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
            sendThemeUpdate()
            // Re-apply theme after first paint to avoid initial flash on cold starts.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.sendThemeUpdate()
            }
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
                sendThemeUpdate()
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

    func makeNSView(context: Context) -> NSView {
        // Wrap WKWebView in a custom NSView to ensure proper cursor handling
        let container = WebViewContainer()
        container.addWebView(webView)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Ensure the web view fills the container
        if let container = nsView as? WebViewContainer {
            container.layoutWebView()
        }
    }
}

/// A container view that properly handles WKWebView's cursor updates in SwiftUI
final class WebViewContainer: NSView {
    private weak var webView: WKWebView?

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
