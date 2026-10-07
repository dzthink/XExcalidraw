import SwiftUI
import ExcalidrawShared

/// 文件树节点视图 - 递归渲染每个节点
struct FileTreeNodeView: View {
    @ObservedObject var node: FileTreeNode
    let level: Int
    @Binding var selectedEntryId: UUID?
    @Binding var editingEntryId: UUID?
    @Binding var editingFileName: String
    let onSelectFile: (ExcalidrawFileEntry) -> Void
    let onOpenInNewWindow: (ExcalidrawFileEntry) -> Void
    let onRename: (ExcalidrawFileEntry) -> Void
    let onCommitRename: (ExcalidrawFileEntry, String) -> Void
    let onCancelRename: () -> Void
    let onDelete: (ExcalidrawFileEntry) -> Void
    let onCreateFile: (FileTreeNode, SiyeDocumentType) -> Void
    let onCreateFolder: (FileTreeNode) -> Void
    let onDeleteFolder: (FileTreeNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if node.isFolder {
                FolderRowView(
                    node: node,
                    level: level,
                    editingEntryId: $editingEntryId,
                    editingFileName: $editingFileName,
                    onCreateFile: onCreateFile,
                    onCreateFolder: onCreateFolder,
                    onDeleteFolder: onDeleteFolder
                )

                FileTreeContentView(
                    node: node,
                    level: level + 1,
                    selectedEntryId: $selectedEntryId,
                    editingEntryId: $editingEntryId,
                    editingFileName: $editingFileName,
                    onSelectFile: onSelectFile,
                    onOpenInNewWindow: onOpenInNewWindow,
                    onRename: onRename,
                    onCommitRename: onCommitRename,
                    onCancelRename: onCancelRename,
                    onDelete: onDelete,
                    onCreateFile: onCreateFile,
                    onCreateFolder: onCreateFolder,
                    onDeleteFolder: onDeleteFolder
                )
            } else if let entry = node.fileEntry {
                FileRowView(
                    entry: entry,
                    level: level,
                    isSelected: selectedEntryId == entry.id,
                    isEditing: editingEntryId == entry.id,
                    editingFileName: $editingFileName,
                    onSelect: {
                        selectedEntryId = entry.id
                        onSelectFile(entry)
                    },
                    onOpenInNewWindow: { onOpenInNewWindow(entry) },
                    onRename: { onRename(entry) },
                    onCommitRename: { onCommitRename(entry, editingFileName) },
                    onCancelRename: onCancelRename,
                    onDelete: { onDelete(entry) }
                )
            }
        }
    }
}

/// 文件树内容视图
struct FileTreeContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var node: FileTreeNode
    var level: Int = 1
    @Binding var selectedEntryId: UUID?
    @Binding var editingEntryId: UUID?
    @Binding var editingFileName: String
    let onSelectFile: (ExcalidrawFileEntry) -> Void
    let onOpenInNewWindow: (ExcalidrawFileEntry) -> Void
    let onRename: (ExcalidrawFileEntry) -> Void
    let onCommitRename: (ExcalidrawFileEntry, String) -> Void
    let onCancelRename: () -> Void
    let onDelete: (ExcalidrawFileEntry) -> Void
    let onCreateFile: (FileTreeNode, SiyeDocumentType) -> Void
    let onCreateFolder: (FileTreeNode) -> Void
    let onDeleteFolder: (FileTreeNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if node.isExpanded {
                ForEach(node.children) { child in
                    FileTreeNodeView(
                        node: child,
                        level: level,
                        selectedEntryId: $selectedEntryId,
                        editingEntryId: $editingEntryId,
                        editingFileName: $editingFileName,
                        onSelectFile: onSelectFile,
                        onOpenInNewWindow: onOpenInNewWindow,
                        onRename: onRename,
                        onCommitRename: onCommitRename,
                        onCancelRename: onCancelRename,
                        onDelete: onDelete,
                        onCreateFile: onCreateFile,
                        onCreateFolder: onCreateFolder,
                        onDeleteFolder: onDeleteFolder
                    )
                }
                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .animation(reduceMotion ? nil : SidebarTreeStyle.expansionAnimation, value: node.isExpanded)
    }
}

/// 文件夹行视图
struct FolderRowView: View {
    @ObservedObject var node: FileTreeNode
    let level: Int
    @Binding var editingEntryId: UUID?
    @Binding var editingFileName: String
    let onCreateFile: (FileTreeNode, SiyeDocumentType) -> Void
    let onCreateFolder: (FileTreeNode) -> Void
    let onDeleteFolder: (FileTreeNode) -> Void

    private var hasChildren: Bool {
        !node.children.isEmpty
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onRemove: (() -> Void)? = nil

    private func toggleExpansion() {
        guard hasChildren else { return }
        editingEntryId = nil
        editingFileName = ""
        withAnimation(reduceMotion ? nil : SidebarTreeStyle.expansionAnimation) {
            node.isExpanded.toggle()
        }
    }

    var body: some View {
        Button(action: toggleExpansion) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(node.isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .opacity(hasChildren ? 1 : 0)
                    .frame(width: SidebarTreeStyle.disclosureWidth)

                Image(systemName: node.isRoot ? "externaldrive.fill" : "folder")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: SidebarTreeStyle.iconWidth)

                Text(node.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .modifier(SidebarTreeRowStyle(level: level))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(node.name)
        .accessibilityValue(hasChildren ? (node.isExpanded ? "Expanded" : "Collapsed") : "Empty folder")
        .accessibilityIdentifier("folder-row-" + node.name)
        .contextMenu {
            Button {
                onCreateFile(node, .excalidraw)
            } label: {
                Label("New Drawing", systemImage: "scribble.variable")
            }
            Button {
                onCreateFile(node, .mindmap)
            } label: {
                Label("New Mind Map", systemImage: "point.3.connected.trianglepath.dotted")
            }

            Button {
                onCreateFolder(node)
            } label: {
                Label("Create Folder", systemImage: "folder.badge.plus")
            }

            Divider()

            Button(role: .destructive) {
                onDeleteFolder(node)
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }

            if hasChildren {
                Divider()

                Button {
                    toggleExpansion()
                } label: {
                    Label(node.isExpanded ? "Collapse" : "Expand", systemImage: node.isExpanded ? "chevron.up" : "chevron.down")
                }
            }
            if let onRemove {
                Divider()
                Button(action: onRemove) {
                    Label("Remove from Sidebar", systemImage: "minus.circle")
                }
            }
        }
    }
}

/// 文件行视图
struct FileRowView: View {
    let entry: ExcalidrawFileEntry
    let level: Int
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editingFileName: String
    let onSelect: () -> Void
    let onOpenInNewWindow: () -> Void
    let onRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onDelete: () -> Void
    @FocusState private var isEditingFocused: Bool
    
    private var displayFileName: String {
        ExcalidrawFileName.displayName(from: entry.fileName)
    }

    var body: some View {
        Group {
            if isEditing {
                HStack(spacing: 6) {
                    Color.clear
                        .frame(width: SidebarTreeStyle.disclosureWidth)

                    TextField("File name", text: $editingFileName)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEditingFocused)
                        .onSubmit {
                            onCommitRename()
                        }
                        .onExitCommand {
                            onCancelRename()
                        }

                    Spacer()
                }
                .modifier(SidebarTreeRowStyle(level: level, isSelected: isSelected))
                .onAppear {
                    isEditingFocused = true
                }
            } else {
                Button {
                    onSelect()
                } label: {
                    HStack(spacing: 6) {
                        Color.clear
                            .frame(width: SidebarTreeStyle.disclosureWidth)

                        Image(systemName: SiyeDocumentType(fileName: entry.fileName) == .mindmap
                              ? "point.3.connected.trianglepath.dotted" : "scribble.variable")
                            .font(.system(size: 12))
                            .frame(width: SidebarTreeStyle.iconWidth)

                        Text(displayFileName)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .modifier(SidebarTreeRowStyle(level: level, isSelected: isSelected))
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityIdentifier("file-row-" + entry.fileName)
        .contextMenu {
            Button(action: onOpenInNewWindow) {
                Label("在新窗口打开", systemImage: "macwindow.badge.plus")
            }
            .accessibilityIdentifier("open-in-new-window")

            Divider()

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

enum SidebarTreeStyle {
    static let rowHeight: CGFloat = 30
    static let indent: CGFloat = 16
    static let disclosureWidth: CGFloat = 12
    static let iconWidth: CGFloat = 16
    static let expansionAnimation = Animation.easeInOut(duration: 0.22)
}

private struct SidebarTreeRowStyle: ViewModifier {
    let level: Int
    var isSelected = false
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.leading, 6 + CGFloat(level) * SidebarTreeStyle.indent)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: SidebarTreeStyle.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(isHovered ? 0.06 : 0))
            }
            .onHover { isHovered = $0 }
    }
}

#Preview {
    let folderId = UUID()
    let entries = [
        ExcalidrawFileEntry(
            folderId: folderId,
            relativePath: "test1.excalidraw",
            fileName: "test1.excalidraw",
            fileURL: URL(fileURLWithPath: "/test/test1.excalidraw"),
            modifiedAt: Date(),
            fileSize: 100
        ),
        ExcalidrawFileEntry(
            folderId: folderId,
            relativePath: "subfolder/test2.excalidraw",
            fileName: "test2.excalidraw",
            fileURL: URL(fileURLWithPath: "/test/subfolder/test2.excalidraw"),
            modifiedAt: Date(),
            fileSize: 200
        ),
        ExcalidrawFileEntry(
            folderId: folderId,
            relativePath: "subfolder/nested/deep.excalidraw",
            fileName: "deep.excalidraw",
            fileURL: URL(fileURLWithPath: "/test/subfolder/nested/deep.excalidraw"),
            modifiedAt: Date(),
            fileSize: 300
        )
    ]

    let root = FileTreeBuilder.buildTree(entries: entries, folderName: "dzx")

    List {
        Section("Documents") {
            FileTreeContentView(
                node: root,
                selectedEntryId: .constant(nil),
                editingEntryId: .constant(nil),
                editingFileName: .constant(""),
                onSelectFile: { _ in },
                onOpenInNewWindow: { _ in },
                onRename: { _ in },
                onCommitRename: { _, _ in },
                onCancelRename: {},
                onDelete: { _ in },
                onCreateFile: { _, _ in },
                onCreateFolder: { _ in },
                onDeleteFolder: { _ in }
            )
        }
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 400)
}
