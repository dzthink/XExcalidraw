#if os(iOS)
import SwiftUI
import Combine
import ExcalidrawShared
import UIKit
import WebKit
import UniformTypeIdentifiers

// MARK: - String Path Extension

extension String {
    var deletingLastPathComponent: String {
        let url = URL(fileURLWithPath: self)
        return url.deletingLastPathComponent().path
    }
}

// MARK: - iOS 26 Liquid Glass Style Extensions

@available(iOS 26.0, *)
extension View {
    func liquidGlassEffect(tint: Color? = nil, isInteractive: Bool = true) -> some View {
        self.modifier(LiquidGlassModifier(tint: tint, isInteractive: isInteractive))
    }
}

@available(iOS 26.0, *)
struct LiquidGlassModifier: ViewModifier {
    let tint: Color?
    let isInteractive: Bool
    
    func body(content: Content) -> some View {
        if isInteractive {
            content
                .glassEffect(.regular.tint(tint ?? .clear).interactive())
        } else {
            content
                .glassEffect(.regular.tint(tint ?? .clear))
        }
    }
}

// 向后兼容的玻璃效果
struct GlassCard<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat
    let isProminent: Bool
    
    init(cornerRadius: CGFloat = 20, isProminent: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.isProminent = isProminent
    }
    
    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(isProminent ? Color.white.opacity(0.3) : Color.white.opacity(0.15), lineWidth: 1)
                )
        } else {
            content
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        }
    }
}

// MARK: - App Entry

@main
struct ExcalidrawIOSApp: App {
    @AppStorage("siye.appearance") private var appearance = AppearancePreference.system.rawValue
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme((AppearancePreference(rawValue: appearance) ?? .system).colorScheme)
        }
    }
}

// MARK: - Content View

private final class CanvasSession: ObservableObject {
    let documentManager: DocumentManager
    let viewModel: WebCanvasViewModel
    private var subscriptions = Set<AnyCancellable>()

    init() {
        let manager: DocumentManager
#if DEBUG
        if let fixture = ProcessInfo.processInfo.environment["SIYE_UI_TEST_FIXTURE"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("UITests-" + UUID().uuidString)
            let defaults = UserDefaults(suiteName: "siye.uitests." + UUID().uuidString)!
            let store = FolderSourceStore(userDefaults: defaults, indexStore: ExcalidrawJSONFileIndexStore(fileURL: root.appendingPathComponent("index.json")))
            manager = DocumentManager(store: store)
            if fixture == "documents" || fixture == "browser" {
                do {
                    let folder = root.appendingPathComponent("Test Documents")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    // Seed both files before indexing to avoid racing an empty scan.
                    for (name, type) in [("Test Canvas", SiyeDocumentType.excalidraw), ("Test Mind Map", SiyeDocumentType.mindmap)] {
                        let data = try JSONSerialization.data(withJSONObject: type.blankScene)
                        try data.write(to: folder.appendingPathComponent(name + type.fileExtension), options: .atomic)
                    }
                    if fixture == "browser" {
                        let nested = folder.appendingPathComponent("Projects/Nested", isDirectory: true)
                        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
                        let data = try JSONSerialization.data(withJSONObject: SiyeDocumentType.mindmap.blankScene)
                        try data.write(to: nested.appendingPathComponent("Nested Idea.mindmap"), options: .atomic)
                    }
                    try manager.addFolder(url: folder)
                } catch {
                    assertionFailure("Failed to prepare UI test documents: \(error)")
                }
            }
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
    @StateObject private var session = CanvasSession()
    private var documentManager: DocumentManager { session.documentManager }
    private var viewModel: WebCanvasViewModel { session.viewModel }
    @State private var selectedEntryId: UUID?
    @State private var navigationPath = NavigationPath()
    @State private var isShowingSettings = false
    

    
    var body: some View {
        Group {
            if documentManager.hasActiveSource {
                mainContentView
            } else {
                OnboardingView(documentManager: documentManager)
            }
        }
        .onAppear {
            viewModel.prewarm()
            restoreLastOpenedFile()
        }
        .onChange(of: documentManager.pendingDraft) { _, draft in
            guard let draft else { return }
            viewModel.restoreDraft(draft)
            documentManager.discardPendingDraft()
        }
    }
    
    @ViewBuilder
    private var mainContentView: some View {
        NavigationStack(path: $navigationPath) {
            FolderListView(
                documentManager: documentManager,
                viewModel: viewModel,
                selectedEntryId: $selectedEntryId,
                navigationPath: $navigationPath
            )
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { isShowingSettings = true } label: { Label("设置", systemImage: "gearshape") } } }
            .sheet(isPresented: $isShowingSettings) { NavigationStack { SiyeSettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { isShowingSettings = false } } } } }
            .navigationDestination(for: FolderDestination.self) { destination in
                FileListView(
                    documentManager: documentManager,
                    viewModel: viewModel,
                    selectedEntryId: $selectedEntryId,
                    navigationPath: $navigationPath,
                    folderPath: destination.folderPath,
                    title: destination.folderName
                )
            }
            .navigationDestination(for: EditorDestination.self) { destination in
                EditorView(
                    documentManager: documentManager,
                    viewModel: viewModel,
                    selectedEntryId: $selectedEntryId,
                    navigationPath: $navigationPath
                )
            }
        }
    }
    
    private func restoreLastOpenedFile() {
        guard documentManager.currentEntry == nil,
              let lastEntry = documentManager.mostRecentEntry() else { return }
        
        do {
            let scene = try documentManager.open(entry: lastEntry)
            viewModel.loadScene(scene)
            selectedEntryId = lastEntry.id
        } catch {}
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @ObservedObject var documentManager: DocumentManager
    @State private var isShowingPicker = false
    
    var body: some View {
        ZStack {
            // 渐变背景
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.25, blue: 0.24).opacity(0.2),
                    Color(red: 0.94, green: 0.72, blue: 0.42).opacity(0.18),
                    Color(red: 0.97, green: 0.94, blue: 0.91).opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                Image("SiyeLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 32))
                .padding(.bottom, 20)
                
                VStack(spacing: 16) {
                    Text("Siye")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    
                    Text("让想法自由生长")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(spacing: 16) {
                    Button {
                        isShowingPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                                .font(.title3)
                            Text("选择文件夹")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: 280)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.orange, .red.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .orange.opacity(0.4), radius: 12, x: 0, y: 6)
                    }
                    
                    if documentManager.folderStore.defaultICloudDocumentsURL != nil {
                        Button {
                            _ = try? documentManager.folderStore.addICloudDocumentsFolder()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "icloud.and.arrow.down")
                                Text("使用 iCloud")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $isShowingPicker) {
            FolderSourcePicker(store: documentManager.folderStore)
        }
    }
}

// MARK: - Folder List View (主文件夹列表)

struct FolderListView: View {
    @ObservedObject var documentManager: DocumentManager
    @ObservedObject var viewModel: WebCanvasViewModel
    @Binding var selectedEntryId: UUID?
    @Binding var navigationPath: NavigationPath
    @State private var fileTreeRoot: FileTreeNode?
    @State private var isShowingSourceSwitcher = false
    @State private var isShowingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var expandedFolders: Set<UUID> = []
    @State private var isFoldersSectionExpanded = true  // 控制文件夹区域整体展开/折叠
    @State private var searchText = ""
    
    private var totalFileCount: Int {
        documentManager.activeSourceEntries.count
    }
    
    private var rootFiles: [ExcalidrawFileEntry] {
        // 获取根目录下的文件（不在任何子文件夹中的文件）
        guard let source = documentManager.activeSource,
              let rootURL = documentManager.folderStore.resolveURL(for: source) else { return [] }
        
        return documentManager.activeSourceEntries.filter { entry in
            let relativePath = entry.fileURL.path.replacingOccurrences(
                of: rootURL.path.appending("/"),
                with: ""
            )
            // 文件直接位于根目录（路径中没有/）
            return !relativePath.contains("/")
        }
    }
    
    private var groupedRootFiles: [(String, [ExcalidrawFileEntry])] {
        let entries = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? rootFiles : documentManager.activeSourceEntries
        return groupEntriesByYear(entries.filter { matchesBrowserSearch($0.relativePath, query: searchText) })
    }
    
    // MARK: - Body Components
    
    private var foldersSectionHeader: some View {
        Button {
            withAnimation {
                isFoldersSectionExpanded.toggle()
            }
        } label: {
            HStack {
                Text("文件夹")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isFoldersSectionExpanded ? "chevron.down" : "chevron.right")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var foldersList: some View {
        ForEach(visibleFolders) { folderNode in
            FolderTreeRow(
                folderNode: folderNode,
                level: 0,
                expandedFolders: $expandedFolders,
                documentManager: documentManager,
                viewModel: viewModel,
                selectedEntryId: $selectedEntryId,
                navigationPath: $navigationPath,
                onDelete: { node in
                    deleteFolder(node)
                }
            )
            
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, expandedFolders.contains(folderNode.id) {
                subFoldersList(for: folderNode)
            }
        }
    }
    
    private func subFoldersList(for folderNode: FileTreeNode) -> some View {
        let subFolders = folderNode.children.filter { $0.isFolder }
        return ForEach(subFolders) { subFolder in
            FolderTreeRow(
                folderNode: subFolder,
                level: 1,
                expandedFolders: $expandedFolders,
                documentManager: documentManager,
                viewModel: viewModel,
                selectedEntryId: $selectedEntryId,
                navigationPath: $navigationPath,
                onDelete: { node in
                    deleteFolder(node)
                }
            )
        }
    }
    
    private var foldersSection: some View {
        Section {
            Button {
                navigationPath.append(FolderDestination(folderPath: nil, folderName: "全部"))
            } label: {
                FolderRowPlain(name: "全部", count: totalFileCount)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("all-documents")

            foldersSectionHeader

            if isFoldersSectionExpanded || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                foldersList
            }
        }
    }
    
    private var topLevelFolders: [FileTreeNode] {
        fileTreeRoot?.children.filter { $0.isFolder } ?? []
    }
    
    private var visibleFolders: [FileTreeNode] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return topLevelFolders }
        func matchingFolders(in node: FileTreeNode) -> [FileTreeNode] {
            node.children.filter { $0.isFolder }.flatMap { child in
                (matchesBrowserSearch(child.path, query: searchText) ? [child] : []) + matchingFolders(in: child)
            }
        }
        return fileTreeRoot.map { matchingFolders(in: $0) } ?? []
    }

    private var filesSections: some View {
        ForEach(groupedRootFiles, id: \.0) { year, yearEntries in
            Section {
                filesList(for: yearEntries)
            } header: {
                Text(year)
                    .font(.title3)
                    .fontWeight(.bold)
                    .textCase(nil)
                    .foregroundStyle(.primary)
            }
        }
    }
    
    private func filesList(for entries: [ExcalidrawFileEntry]) -> some View {
        ForEach(entries) { entry in
            FileRowPlain(
                entry: entry,
                action: { openEntry(entry) },
                onDelete: { deleteEntry(entry) },
                onMove: { }
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    deleteEntry(entry)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    // 移动操作
                } label: {
                    Label("移动", systemImage: "folder")
                }
                .tint(.indigo)
            }
        }
    }
    
    private var newFolderToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isShowingNewFolderAlert = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
        }
    }
    
    private var switchSourceToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isShowingSourceSwitcher = true
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
        }
    }
    
    var body: some View {
        List {
            foldersSection

            if !groupedRootFiles.isEmpty {
                filesSections
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            BrowserBottomBar(
                documentManager: documentManager,
                viewModel: viewModel,
                selectedEntryId: $selectedEntryId,
                navigationPath: $navigationPath,
                searchText: $searchText,
                folderPath: nil
            )
        }
        .alert("新建文件夹", isPresented: $isShowingNewFolderAlert) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) {
                newFolderName = ""
            }
            Button("确定") {
                createFolderWithName(newFolderName)
                newFolderName = ""
            }
        } message: {
            Text("请输入文件夹名称")
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            newFolderToolbarItem
            switchSourceToolbarItem
        }
        .onAppear {
            rescanFolders()
        }
        .onChange(of: documentManager.indexedEntries) { _, _ in
            rescanFolders()
        }
        .onChange(of: documentManager.activeFolderId) { _, _ in
            searchText = ""
            expandedFolders = []
            rescanFolders()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("RefreshFileTree"))) { _ in
            rescanFolders()
        }
        .sheet(isPresented: $isShowingSourceSwitcher) {
            SourceSwitcherSheet(documentManager: documentManager)
        }
    }
    
    private func buildFileTree() {
        guard let activeSource = documentManager.activeSource else { return }
        let entries = documentManager.activeSourceEntries
        fileTreeRoot = FileTreeBuilder.buildTree(
            entries: entries,
            folderName: activeSource.displayName
        )
    }
    
    private func countFiles(in node: FileTreeNode) -> Int {
        if node.isFolder {
            return node.children.reduce(0) { count, child in
                count + countFiles(in: child)
            }
        } else {
            return 1
        }
    }
    
    private func groupEntriesByYear(_ entries: [ExcalidrawFileEntry]) -> [(String, [ExcalidrawFileEntry])] {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        
        var groups: [String: [ExcalidrawFileEntry]] = [:]
        
        for entry in entries {
            let date = entry.lastOpenedAt ?? entry.modifiedAt
            let year = calendar.component(.year, from: date)
            
            let key: String
            if year == currentYear { key = "今年" }
            else if year == currentYear - 1 { key = "去年" }
            else { key = "\(year)年" }
            
            groups[key, default: []].append(entry)
        }
        
        let sortedKeys = groups.keys.sorted { key1, key2 in
            if key1 == "今年" { return true }
            if key2 == "今年" { return false }
            if key1 == "去年" { return true }
            if key2 == "去年" { return false }
            let year1 = Int(key1.replacingOccurrences(of: "年", with: "")) ?? 0
            let year2 = Int(key2.replacingOccurrences(of: "年", with: "")) ?? 0
            return year1 > year2
        }
        
        return sortedKeys.map { ($0, groups[$0]!) }
    }
    
    private func openEntry(_ entry: ExcalidrawFileEntry) {
        do {
            let scene = try documentManager.open(entry: entry)
            viewModel.loadScene(scene)
            selectedEntryId = entry.id
            // 导航到编辑器
            navigationPath.append(EditorDestination(entryId: entry.id))
        } catch {}
    }
    
    private func deleteEntry(_ entry: ExcalidrawFileEntry) {
        do {
            try FileManager.default.removeItem(at: entry.fileURL)
            documentManager.folderStore.removeEntry(id: entry.id)
            if selectedEntryId == entry.id {
                selectedEntryId = nil
            }
        } catch {}
    }
    
    private func createFolderWithName(_ name: String) {
        let folderName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folderName.isEmpty,
              let source = documentManager.activeSource,
              let rootURL = documentManager.folderStore.resolveURL(for: source) else { return }
        
        let newFolderURL = rootURL.appendingPathComponent(folderName, isDirectory: true)
        let uniqueURL = makeUniqueFolderURL(newFolderURL)
        
        do {
            try FileManager.default.createDirectory(at: uniqueURL, withIntermediateDirectories: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.rescanFolders()
            }
        } catch {
            print("创建文件夹失败: \(error)")
        }
    }
    
    private func rescanFolders() {
        // 重新构建文件树以包含新创建的文件夹
        guard let activeSource = documentManager.activeSource else { return }
        let entries = documentManager.activeSourceEntries
        
        // 收集所有文件夹路径
        var folderPaths: [String] = []
        if let rootURL = documentManager.folderStore.resolveURL(for: activeSource) {
            folderPaths = collectAllFolderPaths(at: rootURL)
        }
        
        fileTreeRoot = FileTreeBuilder.buildTree(
            entries: entries,
            folderName: activeSource.displayName,
            folderPaths: folderPaths
        )
    }
    
    private func collectAllFolderPaths(at rootURL: URL) -> [String] {
        var paths: [String] = []
        
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return paths }
        
        for case let url as URL in enumerator {
            do {
                let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory == true {
                    let relativePath = url.path.replacingOccurrences(
                        of: rootURL.path.appending("/"),
                        with: ""
                    )
                    if !relativePath.isEmpty {
                        paths.append(relativePath)
                    }
                }
            } catch {
                continue
            }
        }
        
        return paths.sorted()
    }
    
    private func deleteFolder(_ node: FileTreeNode) {
        guard let source = documentManager.activeSource,
              let rootURL = documentManager.folderStore.resolveURL(for: source) else { return }
        
        let folderURL = resolveFolderURL(for: node, rootURL: rootURL)
        
        do {
            try FileManager.default.removeItem(at: folderURL)
            // 删除该文件夹下的所有索引条目
            deleteEntriesInFolder(node)
            documentManager.refreshIndexes()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.rescanFolders()
            }
        } catch {
            print("删除文件夹失败: \(error)")
        }
    }
    
    private func deleteEntriesInFolder(_ folderNode: FileTreeNode) {
        // 递归删除该文件夹下的所有文件索引
        for child in folderNode.children {
            if child.isFolder {
                deleteEntriesInFolder(child)
            } else if let entry = child.fileEntry {
                documentManager.folderStore.removeEntry(id: entry.id)
            }
        }
    }
    
    private func resolveFolderURL(for node: FileTreeNode, rootURL: URL) -> URL {
        // 如果节点有 path 属性（不为空），直接使用它
        if !node.path.isEmpty {
            return rootURL.appendingPathComponent(node.path, isDirectory: true)
        }
        
        // 否则回退到使用 parent 链构建路径
        var pathComponents: [String] = []
        var current: FileTreeNode? = node
        
        while let n = current, !n.isRoot {
            pathComponents.insert(n.name, at: 0)
            current = n.parent
        }
        
        var url = rootURL
        for component in pathComponents {
            url = url.appendingPathComponent(component, isDirectory: true)
        }
        return url
    }
    
    private func makeUniqueFolderURL(_ url: URL) -> URL {
        var counter = 0
        var uniqueURL = url
        let baseName = url.lastPathComponent
        let parentURL = url.deletingLastPathComponent()
        
        while FileManager.default.fileExists(atPath: uniqueURL.path) {
            counter += 1
            uniqueURL = parentURL.appendingPathComponent("\(baseName) \(counter)", isDirectory: true)
        }
        return uniqueURL
    }
}

// MARK: - All Files Card

struct AllFilesCard: View {
    let count: Int
    
    var body: some View {
        GlassCard(cornerRadius: 20) {
            HStack(spacing: 16) {
                // 简约图标 - 灰色风格
                Image(systemName: "doc.on.doc")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("全部文件")
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    Text("\(count) 个文件")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
    }
}

// MARK: - Folder Card

struct FolderCard: View {
    let name: String
    let count: Int
    
    var body: some View {
        GlassCard(cornerRadius: 16) {
            HStack(spacing: 16) {
                // 简约文件夹图标
                Image(systemName: "folder")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                
                Text(name)
                    .font(.body)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
        }
    }
}

// MARK: - Folder Row Plain (简约分割线样式)

struct FolderRowPlain: View {
    let name: String
    let count: Int
    let level: Int
    let hasChildren: Bool
    let isExpanded: Bool
    let onToggle: (() -> Void)?
    
    init(name: String, count: Int, level: Int = 0, hasChildren: Bool = false, isExpanded: Bool = false, onToggle: (() -> Void)? = nil) {
        self.name = name
        self.count = count
        self.level = level
        self.hasChildren = hasChildren
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 层级缩进
            HStack(spacing: 0) {
                ForEach(0..<level, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 20)
                }
            }
            
            // 展开/收起指示器或占位
            if hasChildren {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
                    .onTapGesture {
                        onToggle?()
                    }
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 20)
            }
            
            Image(systemName: "folder")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 40)
            
            Text(name)
                .font(.body)
                .lineLimit(1)
            
            Spacer()
            
            Text("\(count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Folder Tree Row (树形结构)

struct FolderTreeRow: View {
    @ObservedObject var folderNode: FileTreeNode
    let level: Int
    @Binding var expandedFolders: Set<UUID>
    let documentManager: DocumentManager
    let viewModel: WebCanvasViewModel
    @Binding var selectedEntryId: UUID?
    @Binding var navigationPath: NavigationPath
    let onDelete: (FileTreeNode) -> Void
    
    private var isExpanded: Bool {
        expandedFolders.contains(folderNode.id)
    }
    
    private var subFolders: [FileTreeNode] {
        folderNode.children.filter { $0.isFolder }
    }
    
    private var fileCount: Int {
        countFiles(in: folderNode)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // 层级缩进（不可点击）
            HStack(spacing: 0) {
                ForEach(0..<level, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 20)
                }
            }
            
            // 展开/收起指示器（独立可点击区域）
            if !subFolders.isEmpty {
                Button {
                    toggleExpanded()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 20)
            }
            
            // 文件夹内容（点击打开目录）
            Button {
                navigationPath.append(FolderDestination(
                    folderPath: folderNode.path,
                    folderName: folderNode.name
                ))
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 40)
                    
                    Text(folderNode.name)
                        .font(.body)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text("\(fileCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete(folderNode)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
    
    private func toggleExpanded() {
        if isExpanded {
            expandedFolders.remove(folderNode.id)
        } else {
            expandedFolders.insert(folderNode.id)
        }
    }
    
    private func countFiles(in node: FileTreeNode) -> Int {
        if node.isFolder {
            return node.children.reduce(0) { count, child in
                count + countFiles(in: child)
            }
        } else {
            return 1
        }
    }
}

// MARK: - Navigation Destinations

struct EditorDestination: Hashable {
    let entryId: UUID
}

struct FolderDestination: Hashable {
    // nil opens all documents in the active source.
    let folderPath: String?
    let folderName: String
    
    // Hashable 实现
    func hash(into hasher: inout Hasher) {
        hasher.combine(folderPath)
    }
    
    static func == (lhs: FolderDestination, rhs: FolderDestination) -> Bool {
        lhs.folderPath == rhs.folderPath
    }
}

// MARK: - Browser Search and Creation

private func matchesBrowserSearch(_ text: String, query: String) -> Bool {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return query.isEmpty || text.localizedStandardContains(query)
}

struct BrowserBottomBar: View {
    @ObservedObject var documentManager: DocumentManager
    @ObservedObject var viewModel: WebCanvasViewModel
    @Binding var selectedEntryId: UUID?
    @Binding var navigationPath: NavigationPath
    @Binding var searchText: String
    let folderPath: String?
    @FocusState private var isSearchFocused: Bool
    @State private var isCreating = false
    @State private var creationError: String?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索", text: $searchText)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit { isSearchFocused = false }
                    .accessibilityIdentifier("browser-search")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.quaternary, lineWidth: 0.5))

            Menu {
                Button("新建画布", systemImage: "scribble.variable") {
                    createDocument(type: .excalidraw)
                }
                Button("新建思维导图", systemImage: "point.3.connected.trianglepath.dotted") {
                    createDocument(type: .mindmap)
                }
            } label: {
                Group {
                    if isCreating { ProgressView() }
                    else { Image(systemName: "square.and.pencil").font(.title2) }
                }
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(.quaternary, lineWidth: 0.5))
            }
            .disabled(isCreating)
            .accessibilityLabel("新建文档")
            .accessibilityIdentifier("browser-create")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .alert("新建失败", isPresented: Binding(
            get: { creationError != nil },
            set: { if !$0 { creationError = nil } }
        )) {
            Button("确定", role: .cancel) { creationError = nil }
        } message: {
            Text(creationError ?? "")
        }
    }

    private func createDocument(type: SiyeDocumentType) {
        guard !isCreating else { return }
        isSearchFocused = false
        isCreating = true
        documentManager.createBlankDocument(
            in: documentManager.activeSource?.id,
            relativeFolderPath: folderPath ?? "",
            type: type
        ) { result in
            isCreating = false
            switch result {
            case .success(let scene):
                guard let entry = documentManager.currentEntry else { return }
                viewModel.loadScene(scene)
                selectedEntryId = entry.id
                navigationPath.append(EditorDestination(entryId: entry.id))
            case .failure(let error):
                creationError = error.localizedDescription
            }
        }
    }
}

// MARK: - File List View

struct FileListView: View {
    @ObservedObject var documentManager: DocumentManager
    @ObservedObject var viewModel: WebCanvasViewModel
    @Binding var selectedEntryId: UUID?
    @Binding var navigationPath: NavigationPath
    let folderPath: String?  // nil 表示全部文件
    let title: String
    @State private var refreshTrigger = UUID()
    @State private var isShowingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var currentFolderNode: FileTreeNode?
    
    @State private var searchText = ""

    private var currentFolderFiles: [ExcalidrawFileEntry] {
        _ = refreshTrigger
        return documentManager.activeSourceEntries.filter { entry in
            let parentPath = (entry.relativePath as NSString).deletingLastPathComponent
            let isInFolder = folderPath == nil || parentPath == folderPath
            return isInFolder && matchesBrowserSearch(entry.relativePath, query: searchText)
        }
    }

    private var groupedEntries: [(String, [ExcalidrawFileEntry])] {
        groupEntriesByYear(currentFolderFiles)
    }
    
    private var subFolders: [FileTreeNode] {
        _ = refreshTrigger // 依赖刷新触发器
        if let folderNode = currentFolderNode {
            return folderNode.children.filter { $0.isFolder && matchesBrowserSearch($0.name, query: searchText) }
        }
        return []
    }
    
    var body: some View {
        List {
            // 子目录区域
            if currentFolderNode != nil, !subFolders.isEmpty {
                Section {
                    ForEach(subFolders) { subFolder in
                        let fileCount = countFilesInNode(subFolder)
                        
                        Button {
                            navigationPath.append(FolderDestination(
                                folderPath: subFolder.path,
                                folderName: subFolder.name
                            ))
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "folder")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, height: 40)
                                
                                Text(subFolder.name)
                                    .font(.body)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text("\(fileCount)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteSubFolder(subFolder)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("子文件夹")
                        .font(.title3)
                        .fontWeight(.bold)
                        .textCase(nil)
                        .foregroundStyle(.primary)
                }
            }
            
            // 文件列表区域
            ForEach(groupedEntries, id: \.0) { year, yearEntries in
                Section {
                    ForEach(yearEntries) { entry in
                        FileRowPlain(
                            entry: entry,
                            action: { openEntry(entry) },
                            onDelete: { deleteEntry(entry) },
                            onMove: { /* 移动操作 */ }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteEntry(entry)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                // 移动操作
                            } label: {
                                Label("移动", systemImage: "folder")
                            }
                            .tint(.indigo)
                        }
                    }
                } header: {
                    Text(year)
                        .font(.title3)
                        .fontWeight(.bold)
                        .textCase(nil)
                        .foregroundStyle(.primary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            BrowserBottomBar(
                documentManager: documentManager,
                viewModel: viewModel,
                selectedEntryId: $selectedEntryId,
                navigationPath: $navigationPath,
                searchText: $searchText,
                folderPath: folderPath
            )
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if currentFolderNode != nil {
                    Button {
                        createNewFolderInCurrentDirectory()
                    } label: {
                        Label("新建文件夹", systemImage: "folder.badge.plus")
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .onAppear {
            // 根据 folderPath 初始化 currentFolderNode
            loadFolderNode()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("RefreshFileTree"))) { _ in
            // 触发刷新以重新计算 entries 和 subFolders
            refreshTrigger = UUID()
            // 重新扫描文件夹以更新 folderNode 的 children
            if let folderNode = currentFolderNode {
                rescanCurrentFolder(folderNode)
            }
        }
        .alert("新建文件夹", isPresented: $isShowingNewFolderAlert) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) {
                newFolderName = ""
            }
            Button("确定") {
                createFolderWithName(newFolderName)
                newFolderName = ""
            }
        } message: {
            Text("请输入文件夹名称")
        }
    }
    
    private func loadFolderNode() {
        guard let path = folderPath, !path.isEmpty else {
            currentFolderNode = nil
            return
        }
        
        guard let source = documentManager.activeSource,
              let rootURL = documentManager.folderStore.resolveURL(for: source) else { return }
        
        // 构建文件夹节点
        let folderURL = rootURL.appendingPathComponent(path, isDirectory: true)
        let folderName = folderURL.lastPathComponent
        
        // 创建文件夹节点并扫描内容
        let node = FileTreeNode(
            name: folderName,
            path: path,
            isFolder: true
        )
        
        // 扫描子文件夹
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
            
            for url in contents {
                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues?.isDirectory == true {
                    let subFolderName = url.lastPathComponent
                    let subPath = "\(path)/\(subFolderName)"
                    let subNode = FileTreeNode(
                        name: subFolderName,
                        path: subPath,
                        isFolder: true,
                        parent: node
                    )
                    node.children.append(subNode)
                }
            }
        } catch {
            print("扫描文件夹失败: \(error)")
        }
        
        currentFolderNode = node
    }
    
    private func rescanCurrentFolder(_ node: FileTreeNode) {
        guard let source = documentManager.activeSource,
              let rootURL = documentManager.folderStore.resolveURL(for: source) else { return }
        
        let folderURL = resolveFolderURL(for: node, rootURL: rootURL)
        
        // 扫描文件夹内容
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
            
            // 查找新创建的子文件夹并添加到 node.children
            for url in contents {
                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues?.isDirectory == true {
                    let folderName = url.lastPathComponent
                    // 检查是否已存在
                    if !node.children.contains(where: { $0.name == folderName && $0.isFolder }) {
                        let newNode = FileTreeNode(
                            name: folderName,
                            path: node.path.isEmpty ? folderName : "\(node.path)/\(folderName)",
                            isFolder: true,
                            parent: node
                        )
                        node.children.append(newNode)
                    }
                }
            }
        } catch {}
    }
    
    private func getEntries(from node: FileTreeNode) -> [ExcalidrawFileEntry] {
        var entries: [ExcalidrawFileEntry] = []
        if let entry = node.fileEntry { entries.append(entry) }
        for child in node.children {
            entries.append(contentsOf: getEntries(from: child))
        }
        return entries.sorted {
            ($0.lastOpenedAt ?? $0.modifiedAt) > ($1.lastOpenedAt ?? $1.modifiedAt)
        }
    }
    
    private func groupEntriesByYear(_ entries: [ExcalidrawFileEntry]) -> [(String, [ExcalidrawFileEntry])] {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        
        var groups: [String: [ExcalidrawFileEntry]] = [:]
        
        for entry in entries {
            let date = entry.lastOpenedAt ?? entry.modifiedAt
            let year = calendar.component(.year, from: date)
            
            let key: String
            if year == currentYear { key = "今年" }
            else if year == currentYear - 1 { key = "去年" }
            else { key = "\(year)年" }
            
            groups[key, default: []].append(entry)
        }
        
        let sortedKeys = groups.keys.sorted { key1, key2 in
            if key1 == "今年" { return true }
            if key2 == "今年" { return false }
            if key1 == "去年" { return true }
            if key2 == "去年" { return false }
            let year1 = Int(key1.replacingOccurrences(of: "年", with: "")) ?? 0
            let year2 = Int(key2.replacingOccurrences(of: "年", with: "")) ?? 0
            return year1 > year2
        }
        
        return sortedKeys.map { ($0, groups[$0]!) }
    }
    
    private func openEntry(_ entry: ExcalidrawFileEntry) {
        do {
            let scene = try documentManager.open(entry: entry)
            viewModel.loadScene(scene)
            selectedEntryId = entry.id
            // 导航到编辑器
            navigationPath.append(EditorDestination(entryId: entry.id))
        } catch {}
    }
    
    private func countFilesInNode(_ node: FileTreeNode) -> Int {
        if node.isFolder {
            return node.children.reduce(0) { count, child in
                count + countFilesInNode(child)
            }
        } else {
            return 1
        }
    }
    
    private func createNewFolderInCurrentDirectory() {
        // 显示输入对话框
        isShowingNewFolderAlert = true
    }
    
    private func createFolderWithName(_ name: String) {
        let folderName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folderName.isEmpty,
              let folderNode = currentFolderNode,
              let source = documentManager.activeSource,
              let rootURL = documentManager.folderStore.resolveURL(for: source) else { return }
        
        let parentURL = resolveFolderURL(for: folderNode, rootURL: rootURL)
        let newFolderURL = parentURL.appendingPathComponent(folderName, isDirectory: true)
        let uniqueURL = makeUniqueFolderURL(newFolderURL)
        
        do {
            try FileManager.default.createDirectory(at: uniqueURL, withIntermediateDirectories: true)
            // 刷新文件树
            NotificationCenter.default.post(name: .init("RefreshFileTree"), object: nil)
        } catch {
            print("创建文件夹失败: \(error)")
        }
    }
    
    private func deleteEntry(_ entry: ExcalidrawFileEntry) {
        do {
            try FileManager.default.removeItem(at: entry.fileURL)
            documentManager.folderStore.removeEntry(id: entry.id)
            if selectedEntryId == entry.id {
                selectedEntryId = nil
            }
        } catch {}
    }
    
    private func deleteSubFolder(_ subFolder: FileTreeNode) {
        guard let source = documentManager.activeSource,
              let rootURL = documentManager.folderStore.resolveURL(for: source),
              let parentNode = currentFolderNode else { return }
        
        let folderURL = resolveFolderURL(for: subFolder, rootURL: rootURL)
        
        do {
            try FileManager.default.removeItem(at: folderURL)
            // 从父节点中移除
            parentNode.children.removeAll { $0.id == subFolder.id }
            // 触发刷新
            refreshTrigger = UUID()
        } catch {
            print("删除子文件夹失败: \(error)")
        }
    }
    
    private func resolveFolderURL(for node: FileTreeNode, rootURL: URL) -> URL {
        // 优先使用 node 的 path 属性（相对路径）
        if !node.path.isEmpty {
            return rootURL.appendingPathComponent(node.path, isDirectory: true)
        }
        
        // 回退：使用 parent 链构建路径
        var pathComponents: [String] = []
        var current: FileTreeNode? = node
        
        while let n = current, !n.isRoot {
            pathComponents.insert(n.name, at: 0)
            current = n.parent
        }
        
        var url = rootURL
        for component in pathComponents {
            url = url.appendingPathComponent(component, isDirectory: true)
        }
        return url
    }
    
    private func makeUniqueFolderURL(_ url: URL) -> URL {
        var counter = 0
        var uniqueURL = url
        let baseName = url.lastPathComponent
        let parentURL = url.deletingLastPathComponent()
        
        while FileManager.default.fileExists(atPath: uniqueURL.path) {
            counter += 1
            uniqueURL = parentURL.appendingPathComponent("\(baseName) \(counter)", isDirectory: true)
        }
        return uniqueURL
    }
}

// MARK: - File Row (卡片样式，保留但可能不再使用)

struct FileRow: View {
    let entry: ExcalidrawFileEntry
    let action: () -> Void
    let onDelete: (() -> Void)?
    let onMove: (() -> Void)?
    
    private var displayName: String {
        SiyeDocumentType.displayName(from: entry.fileName)
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: entry.modifiedAt)
    }
    
    var body: some View {
        Button(action: action) {
            GlassCard(cornerRadius: 16) {
                HStack(spacing: 12) {
                    // 文件图标
                    Image(systemName: SiyeDocumentType(fileName: entry.fileName) == .mindmap ? "point.3.connected.trianglepath.dotted" : "scribble.variable")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(displayName)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Text(dateString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // 缩略图占位
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.systemGray5))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "scribble")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                        )
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // 左滑：删除
            if let onDelete = onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            // 右滑：移动
            if let onMove = onMove {
                Button {
                    onMove()
                } label: {
                    Label("移动", systemImage: "folder")
                }
                .tint(.indigo)
            }
        }
    }
}

// MARK: - File Row Plain (简约分割线样式)

struct FileRowPlain: View {
    let entry: ExcalidrawFileEntry
    let action: () -> Void
    let onDelete: (() -> Void)?
    let onMove: (() -> Void)?
    
    private var displayName: String {
        SiyeDocumentType.displayName(from: entry.fileName)
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: entry.modifiedAt)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 文件图标
            Image(systemName: SiyeDocumentType(fileName: entry.fileName) == .mindmap ? "point.3.connected.trianglepath.dotted" : "scribble.variable")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(dateString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // 缩略图占位
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.systemGray5))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "scribble")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                )
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
    }
}

// MARK: - Editor View

struct EditorView: View {
    @ObservedObject var documentManager: DocumentManager
    @ObservedObject var viewModel: WebCanvasViewModel
    @Binding var selectedEntryId: UUID?
    @Binding var navigationPath: NavigationPath
    @State private var isEditingTitle = false
    @State private var editableTitle = ""
    @FocusState private var titleFieldFocused: Bool
    
    private var currentFileName: String {
        documentManager.currentEntry.map { SiyeDocumentType.displayName(from: $0.fileName) } ?? "未命名"
    }
    
    var body: some View {
        ZStack {
            WebCanvasView(webView: viewModel.webView)
                .ignoresSafeArea()
                .accessibilityIdentifier(viewModel.isCanvasReady ? "editor-ready" : "editor-loading")
            
            if !viewModel.isCanvasReady {
                LoadingView()
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
        .toolbar {
            // 可编辑的标题
            ToolbarItem(placement: .principal) {
                if isEditingTitle {
                    TextField("文件名", text: $editableTitle)
                        .focused($titleFieldFocused)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .onSubmit {
                            commitRename()
                        }
                        .onChange(of: titleFieldFocused) { oldValue, newValue in
                            if !newValue {
                                // 失去焦点时自动保存
                                commitRename()
                            }
                        }
                } else {
                    Button {
                        editableTitle = currentFileName
                        isEditingTitle = true
                        titleFieldFocused = true
                    } label: {
                        Text(currentFileName)
                            .font(.headline)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    // 直接弹出导航栈，返回上一层
                    navigationPath.removeLast()
                    DispatchQueue.main.async {
                        documentManager.clearCurrentEntry()
                        selectedEntryId = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                        Text("返回")
                    }
                }
            }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            viewModel.requestExport(format: "png")
                        } label: {
                            Label("导出为 PNG", systemImage: "photo")
                        }
                        
                        Button {
                            viewModel.requestExport(format: "svg")
                        } label: {
                            Label("导出为 SVG", systemImage: "doc.text")
                        }
                        
                        Button {
                            viewModel.requestExport(format: "json")
                        } label: {
                            Label("导出为 JSON", systemImage: "doc.json")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }
                }
            }
    }
    
    private func commitRename() {
        let newName = editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != currentFileName else {
            isEditingTitle = false
            return
        }
        
        do {
            try documentManager.renameCurrentEntry(to: newName)
            if let entry = documentManager.currentEntry {
                viewModel.updateDocId(entry.fileURL.path)
            }
            isEditingTitle = false
        } catch {
            // 显示错误提示
            print("重命名失败: \(error.localizedDescription)")
            isEditingTitle = false
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.secondary)
            Text("加载画布中...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Source Switcher Sheet

struct SourceSwitcherSheet: View {
    @ObservedObject var documentManager: DocumentManager
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingPicker = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("当前存储库") {
                    if let activeSource = documentManager.activeSource {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.orange)
                            }
                            
                            Text(activeSource.displayName)
                                .font(.body)
                            
                            Spacer()
                            
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                
                Section {
                    Button {
                        isShowingPicker = true
                    } label: {
                        Label("打开其他文件夹", systemImage: "folder.badge.plus")
                    }
                }
                
                if documentManager.sources.count > 1 {
                    Section("其他存储库") {
                        ForEach(documentManager.sources.filter { $0.id != documentManager.activeSource?.id }) { source in
                            Button {
                                documentManager.switchToSource(id: source.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.gray.opacity(0.15))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "folder")
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Text(source.displayName)
                                    
                                    Spacer()
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
            }
            .navigationTitle("切换存储库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingPicker) {
                FolderSourcePicker(store: documentManager.folderStore)
            }
        }
    }
}

// MARK: - Web Canvas View

struct WebCanvasView: UIViewRepresentable {
    let webView: WKWebView
    
    func makeUIView(context: Context) -> WKWebView {
        webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Web Canvas View Model

private final class NodeKeyboardAccessory: UIView {
    var onAction: ((String) -> Void)?
    var onVisibility: ((Bool) -> Void)?
    var onLayout: (() -> Void)?

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 68) }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 68))
        autoresizingMask = [.flexibleWidth]
        accessibilityIdentifier = "mindmap-keyboard-accessory"
        backgroundColor = .clear
        let capsule = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.layer.cornerRadius = 27
        capsule.clipsToBounds = true
        addSubview(capsule)
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        capsule.contentView.addSubview(scroll)
        let actions = UIStackView()
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.axis = .horizontal
        actions.spacing = 4
        scroll.addSubview(actions)
        let items: [(String, String?)] = [
            ("文字样式", nil), ("列表", "list.bullet"), ("表格", "tablecells"),
            ("插入图片", "photo"), ("代码", "chevron.left.forwardslash.chevron.right"),
            ("链接", "link"),
            ("撤销", "arrow.uturn.backward"), ("重做", "arrow.uturn.forward")
        ]
        for (label, symbol) in items {
            let button = makeButton(label, symbol: symbol)
            if symbol == nil { button.setTitle("格式", for: .normal) }
            actions.addArrangedSubview(button)
        }
        let dismiss = makeButton("收起键盘", symbol: "keyboard.chevron.compact.down")
        dismiss.translatesAutoresizingMaskIntoConstraints = false
        capsule.contentView.addSubview(dismiss)
        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            capsule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            capsule.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            capsule.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            dismiss.trailingAnchor.constraint(equalTo: capsule.contentView.trailingAnchor, constant: -4),
            dismiss.topAnchor.constraint(equalTo: capsule.contentView.topAnchor),
            dismiss.bottomAnchor.constraint(equalTo: capsule.contentView.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: capsule.contentView.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: dismiss.leadingAnchor, constant: -4),
            scroll.topAnchor.constraint(equalTo: capsule.contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: capsule.contentView.bottomAnchor),
            actions.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            actions.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            actions.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            actions.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeButton(_ label: String, symbol: String?) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityLabel = label
        button.tintColor = .label
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        if let symbol { button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)), for: .normal) }
        button.widthAnchor.constraint(equalToConstant: label == "文字样式" ? 64 : 48).isActive = true
        button.addAction(UIAction { [weak self] _ in self?.onAction?(label) }, for: .touchUpInside)
        return button
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onVisibility?(window != nil)
    }
}

private final class CanvasWebView: WKWebView, UIDocumentPickerDelegate, UIGestureRecognizerDelegate {
    private lazy var nodeAccessory: NodeKeyboardAccessory = {
        let view = NodeKeyboardAccessory()
        view.onAction = { [weak self] action in
            guard let self else { return }
            if action == "收起键盘" {
                self.endEditing(true)
                self.evaluateJavaScript("window.dispatchEvent(new CustomEvent('siye-node-toolbar-action', {detail: '收起键盘'}))", completionHandler: nil)
                return
            }
            if action == "插入图片" {
                self.presentImagePicker()
                return
            }
            self.updateAccessoryFrame()
            guard let data = try? JSONEncoder().encode(action), let value = String(data: data, encoding: .utf8) else { return }
            self.evaluateJavaScript("window.dispatchEvent(new CustomEvent('siye-node-toolbar-action', {detail: \(value)}))", completionHandler: nil)

        }
        view.onVisibility = { [weak self] visible in
            self?.evaluateJavaScript("window.siyeNativeKeyboardVisible = \(visible ? "true" : "false"); window.dispatchEvent(new Event('siye-native-keyboard'));", completionHandler: nil)
        }
        view.onLayout = { [weak self] in self?.updateAccessoryFrame() }
        return view
    }()

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        let nodePress = UILongPressGestureRecognizer(target: self, action: #selector(showNodeMenu(_:)))
        nodePress.name = "siye-node-long-press"
        nodePress.minimumPressDuration = 0.35
        nodePress.allowableMovement = 10
        nodePress.delegate = self
        addGestureRecognizer(nodePress)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAccessoryFrame), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer.name == "siye-node-long-press" else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        return usesNodeToolbar && gestureRecognizer.numberOfTouches == 1
    }

    @objc private func showNodeMenu(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, bounds.width > 0 else { return }
        let point = gesture.location(in: self)
        let x = point.x / bounds.width
        let y = (point.y - scrollView.adjustedContentInset.top) / bounds.width
        evaluateJavaScript("window.dispatchEvent(new CustomEvent('siye-node-long-press', {detail: {x: \(x) * window.innerWidth, y: \(y) * window.innerWidth}}));", completionHandler: nil)
    }

    @objc private func updateAccessoryFrame() {
        guard nodeAccessory.window != nil, bounds.width > 0 else { return }
        // WKWebView places page coordinates below its adjusted top safe-area inset.
        let top = (nodeAccessory.convert(nodeAccessory.bounds, to: self).minY - scrollView.adjustedContentInset.top) / bounds.width
        evaluateJavaScript("window.siyeNativeKeyboardTop = \(top) * window.innerWidth; window.dispatchEvent(new Event('siye-native-keyboard'));", completionHandler: nil)
    }

    private func presentImagePicker() {
        guard var presenter = window?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        // Clear WebKit's input focus before a modal steals the native responder.
        endEditing(true)
        evaluateJavaScript("document.activeElement?.blur()", completionHandler: nil)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.png, .jpeg, .gif, UTType("org.webmproject.webp") ?? .image], asCopy: true)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true) { [weak self] in self?.resumeNodeEditing() }
    }

    private func resumeNodeEditing() {
        becomeFirstResponder()
        evaluateJavaScript("window.dispatchEvent(new CustomEvent('siye-node-toolbar-action', {detail: '恢复编辑'}))", completionHandler: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let data = try? Data(contentsOf: url), data.count <= 10 * 1024 * 1024 else { return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
        let payload = ["base64": data.base64EncodedString(), "name": url.lastPathComponent, "mime": mime]
        guard let json = try? JSONSerialization.data(withJSONObject: payload), let value = String(data: json, encoding: .utf8) else { return }
        controller.dismiss(animated: true) { [weak self] in
            self?.resumeNodeEditing()
            self?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('siye-node-toolbar-image', {detail: \(value)}))", completionHandler: nil)
        }
    }

    var usesNodeToolbar = false {
        didSet {
            if oldValue != usesNodeToolbar { reloadInputViews() }
        }
    }

    // UIKit positions this accessory for every keyboard, including third-party IMEs.
    override var inputAccessoryView: UIView? {
        usesNodeToolbar ? nodeAccessory : super.inputAccessoryView
    }
}

final class WebCanvasViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    @Published var isCanvasReady = false
    @Published var hasUnsavedChanges = false
    let webView: WKWebView

    private var currentDocumentID: String?
    private var sceneGeneration = 0
    private let messageHandlerName = "bridge"
    private let aiEnabledKey = "aiEnabled"
    private var didSendInitialScene = false
    private var isBridgeReady = false
    private var didStartLoading = false
    private let documentManager: DocumentManager
    private let aiModule: AIModule
    private let schemeHandler = BundleSchemeHandler()
    private var pendingScenePayload: [String: Any]?

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
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "app")
        config.userContentController = contentController
        contentController.addUserScript(WKUserScript(source: "window.siyeNativeKeyboardAccessory = true; window.siyeNativeKeyboardVisible = false;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        self.webView = CanvasWebView(frame: .zero, configuration: config)
        super.init()
        contentController.add(self, name: messageHandlerName)
        webView.navigationDelegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(flushOnBackground), name: UIApplication.willResignActiveNotification, object: nil)
        
        // 设置 WebView 背景透明，不干扰系统颜色
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
    }

    func prewarm() {
        load()
    }

    func load() {
        guard !didStartLoading else { return }
        didStartLoading = true
        isCanvasReady = false
        
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
        loadInitialScene()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == messageHandlerName,
              let payloadString = message.body as? String,
              let data = payloadString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              let payload = json["payload"] as? [String: Any] else { return }

        if type == "saveScene" {
            handleSave(payload: payload)
        } else if type == "openLink" {
            if let value = payload["url"] as? String, let url = URL(string: value), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                UIApplication.shared.open(url)
            }
        } else if type == "saveAttachment" {
            handleSaveAttachment(payload: payload)
        } else if type == "didChange" {
            hasUnsavedChanges = payload["dirty"] as? Bool ?? true
        } else if type == "webReady" {
            isCanvasReady = true
            isBridgeReady = true
            flushPendingSceneIfNeeded()
            sendAIConfig()
        } else if type == "exportResult" {
            handleExport(payload: payload)
        } else if type == "requestAI" {
            handleRequestAI(payload: payload)
        }
    }

    private func handleExport(payload: [String: Any]) {
        guard let format = payload["format"] as? String,
              let dataBase64 = payload["dataBase64"] as? String,
              let exportData = Data(base64Encoded: dataBase64) else { return }
        
        let ext = format == "png" ? "png" : format == "svg" ? "svg" : "json"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "Export-\(formatter.string(from: Date())).\(ext)"
        
        guard let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = baseURL.appendingPathComponent(fileName)
        
        try? exportData.write(to: fileURL)
        
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
            let activityController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            rootViewController.present(activityController, animated: true)
        }
    }

    private func handleSave(payload: [String: Any]) {
        let requestId = payload["requestId"] as? String ?? ""
        guard let docId = payload["docId"] as? String, let raw = payload["sceneJson"] else {
            send(type: "saveResult", payload: ["requestId": requestId, "success": false, "error": "保存数据不完整"])
            return
        }
        let scene: Any
        if let text = raw as? String, let data = text.data(using: .utf8), let parsed = try? JSONSerialization.jsonObject(with: data) { scene = parsed } else { scene = raw }
        guard JSONSerialization.isValidJSONObject(scene) else {
            send(type: "saveResult", payload: ["requestId": requestId, "success": false, "error": "文档格式无效"])
            return
        }
        documentManager.saveScene(docId: docId, sceneJson: scene) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    if self.currentDocumentID == docId { self.hasUnsavedChanges = false }
                    self.send(type: "saveResult", payload: ["requestId": requestId, "docId": docId, "success": true])
                case .failure(let error):
                    self.send(type: "saveResult", payload: ["requestId": requestId, "docId": docId, "success": false, "error": error.localizedDescription])
                }
            }
        }
    }

    @objc private func flushOnBackground() {
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "Save mindmap") {
            if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid }
        }
        flushEditing { _ in
            if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid }
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
              let imageData = Data(base64Encoded: encoded),
              imageData.count <= 10 * 1024 * 1024,
              let context = documentManager.attachmentContext(docId: docId) else {
            send(type: "attachmentSaveFailed", payload: ["requestId": requestId, "error": "无法保存图片附件"])
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
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

    func createNewDocument(type: SiyeDocumentType = .excalidraw) {
        documentManager.createBlankDocument(type: type) { [weak self] result in
            guard let self else { return }
            if case .success(let scene) = result {
                self.queueScenePayload([
                    "docId": scene.docId,
                    "sceneJson": scene.sceneJson,
                    "readOnly": scene.readOnly
                ])
                self.hasUnsavedChanges = false
            }
        }
    }

    func loadScene(_ scene: DocumentScene) {
        let payload: [String: Any] = [
            "docId": scene.docId,
            "sceneJson": scene.sceneJson,
            "readOnly": scene.readOnly
        ]
        if isBridgeReady {
            send(type: "loadScene", payload: payload)
        } else {
            queueScenePayload(payload)
        }
        hasUnsavedChanges = false
    }

    func updateDocId(_ newDocId: String) {
        pendingScenePayload?["docId"] = newDocId
        if isBridgeReady {
            send(type: "updateDocId", payload: ["docId": newDocId])
        }
    }

    private func loadInitialScene() {
        if let entry = documentManager.mostRecentEntry() {
            do {
                let scene = try documentManager.open(entry: entry)
                loadScene(scene)
            } catch {
                createBlankScene()
            }
            return
        }
        createBlankScene()
    }
    
    private func createBlankScene() {
        let payload: [String: Any] = [
            "docId": UUID().uuidString,
            "sceneJson": ["elements": [], "appState": [:]],
            "readOnly": false
        ]
        queueScenePayload(payload)
    }

    func restoreDraft(_ draft: DocumentDraft) {
        queueScenePayload([
            "docId": draft.docId,
            "sceneJson": draft.sceneJson,
            "readOnly": false
        ])
        hasUnsavedChanges = true
    }

    func requestExport(format: String) {
        send(type: "export", payload: ["format": format])
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
            (webView as? CanvasWebView)?.usesNodeToolbar = SiyeDocumentType(fileName: docId) == .mindmap || (payload["sceneJson"] as? [String: Any])?["format"] as? String == "siye-mindmap"
            let context = documentManager.attachmentContext(docId: docId)
            schemeHandler.setAttachmentContext(documentURL: context?.documentURL, repositoryURL: context?.repositoryURL)
        }
        let envelope: [String: Any] = [
            "version": "1.0",
            "type": type,
            "payload": payload
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        let js = "window.bridgeDispatch && window.bridgeDispatch(\(jsonString.debugDescription))"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func sendAIConfig() {
        guard isBridgeReady else { return }
        send(type: "aiConfig", payload: [
            "enabled": isAIEnabled
        ])
    }

    private func handleRequestAI(payload: [String: Any]) {
        let docId = payload["docId"] as? String ?? UUID().uuidString
        let prompt = payload["prompt"] as? String
        aiModule.generateScene(docId: docId, prompt: prompt) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sceneJson):
                    self?.queueScenePayload([
                        "docId": docId,
                        "sceneJson": sceneJson,
                        "readOnly": false
                    ])
                case .failure:
                    break
                }
            }
        }
    }
}

// MARK: - Bundle Scheme Handler

final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    private let attachmentLock = NSLock()
    private var attachmentDocumentURL: URL?
    private var attachmentRepositoryURL: URL?

    func setAttachmentContext(documentURL: URL?, repositoryURL: URL?) {
        attachmentLock.lock()
        attachmentDocumentURL = documentURL
        attachmentRepositoryURL = repositoryURL
        attachmentLock.unlock()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "BundleSchemeHandler", code: 1))
            return
        }
        var resourcePath = url.host ?? ""
        resourcePath += url.path
        if resourcePath.hasPrefix("/") { resourcePath.removeFirst() }
        if resourcePath.isEmpty { resourcePath = "index.html" }
        if resourcePath == "mindmap-attachment" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let docId = query.first(where: { $0.name == "docId" })?.value
            let path = query.first(where: { $0.name == "path" })?.value
            attachmentLock.lock()
            let documentURL = attachmentDocumentURL
            let repositoryURL = attachmentRepositoryURL
            attachmentLock.unlock()
            guard let docId, let path, let documentURL, let repositoryURL,
                  docId == documentURL.path,
                  let fileURL = MindMapAttachmentStore.resolve(
                    relativePath: path,
                    documentURL: documentURL,
                    repositoryURL: repositoryURL
                  ),
                  let data = try? Data(contentsOf: fileURL) else {
                urlSchemeTask.didFailWithError(NSError(domain: "BundleSchemeHandler", code: 3))
                return
            }
            let response = URLResponse(
                url: url,
                mimeType: mimeType(for: fileURL.pathExtension),
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
            return
        }
        
        guard let baseURL = Bundle.main.resourceURL,
              let data = try? Data(contentsOf: baseURL.appendingPathComponent(resourcePath)) else {
            urlSchemeTask.didFailWithError(NSError(domain: "BundleSchemeHandler", code: 2))
            return
        }
        
        let mimeType = mimeType(for: (resourcePath as NSString).pathExtension)
        let response = URLResponse(
            url: url,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: mimeType.hasPrefix("text/") ? "utf-8" : nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html"
        case "js": return "application/javascript"
        case "css": return "text/css"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }
}

#else
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Siye for iOS")
    }
}
#endif
