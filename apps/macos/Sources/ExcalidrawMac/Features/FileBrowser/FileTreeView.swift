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
    let onRename: (ExcalidrawFileEntry) -> Void
    let onCommitRename: (ExcalidrawFileEntry, String) -> Void
    let onCancelRename: () -> Void
    let onDelete: (ExcalidrawFileEntry) -> Void
    let onCreateFile: (FileTreeNode) -> Void
    let onCreateFolder: (FileTreeNode) -> Void
    let onDeleteFolder: (FileTreeNode) -> Void

    var body: some View {
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

            if node.isExpanded {
                ForEach(node.children) { child in
                    FileTreeNodeView(
                        node: child,
                        level: level + 1,
                        selectedEntryId: $selectedEntryId,
                        editingEntryId: $editingEntryId,
                        editingFileName: $editingFileName,
                        onSelectFile: onSelectFile,
                        onRename: onRename,
                        onCommitRename: onCommitRename,
                        onCancelRename: onCancelRename,
                        onDelete: onDelete,
                        onCreateFile: onCreateFile,
                        onCreateFolder: onCreateFolder,
                        onDeleteFolder: onDeleteFolder
                    )
                }
            }
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
                onRename: { onRename(entry) },
                onCommitRename: { onCommitRename(entry, editingFileName) },
                onCancelRename: onCancelRename,
                onDelete: { onDelete(entry) }
            )
        }
    }
}

/// 文件树内容视图
struct FileTreeContentView: View {
    @ObservedObject var node: FileTreeNode
    @Binding var selectedEntryId: UUID?
    @Binding var editingEntryId: UUID?
    @Binding var editingFileName: String
    let onSelectFile: (ExcalidrawFileEntry) -> Void
    let onRename: (ExcalidrawFileEntry) -> Void
    let onCommitRename: (ExcalidrawFileEntry, String) -> Void
    let onCancelRename: () -> Void
    let onDelete: (ExcalidrawFileEntry) -> Void
    let onCreateFile: (FileTreeNode) -> Void
    let onCreateFolder: (FileTreeNode) -> Void
    let onDeleteFolder: (FileTreeNode) -> Void

    var body: some View {
        if node.isExpanded {
            ForEach(node.children) { child in
                FileTreeNodeView(
                    node: child,
                    level: 0,
                    selectedEntryId: $selectedEntryId,
                    editingEntryId: $editingEntryId,
                    editingFileName: $editingFileName,
                    onSelectFile: onSelectFile,
                    onRename: onRename,
                    onCommitRename: onCommitRename,
                    onCancelRename: onCancelRename,
                    onDelete: onDelete,
                    onCreateFile: onCreateFile,
                    onCreateFolder: onCreateFolder,
                    onDeleteFolder: onDeleteFolder
                )
            }
        }
    }
}

/// 文件夹行视图
struct FolderRowView: View {
    @ObservedObject var node: FileTreeNode
    let level: Int
    @Binding var editingEntryId: UUID?
    @Binding var editingFileName: String
    let onCreateFile: (FileTreeNode) -> Void
    let onCreateFolder: (FileTreeNode) -> Void
    let onDeleteFolder: (FileTreeNode) -> Void

    private var hasChildren: Bool {
        !node.children.isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            if hasChildren {
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
            } else {
                Color.clear
                    .frame(width: 20, height: 28)
            }

            Button {
                editingEntryId = nil
                editingFileName = ""
                withAnimation(.easeInOut(duration: 0.15)) {
                    node.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: node.isExpanded && hasChildren ? "folder.fill" : "folder")
                        .foregroundStyle(.orange.gradient)
                        .font(.system(size: 14))

                    Text(node.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, CGFloat(level * 16))
        .padding(.vertical, 1)
        .contextMenu {
            Button {
                onCreateFile(node)
            } label: {
                Label("Create File", systemImage: "doc.badge.plus")
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
                    withAnimation(.easeInOut(duration: 0.15)) {
                        node.isExpanded.toggle()
                    }
                } label: {
                    Label(node.isExpanded ? "Collapse" : "Expand", systemImage: node.isExpanded ? "chevron.up" : "chevron.down")
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
                        .frame(width: 20)

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
                .padding(.vertical, 2)
                .onAppear {
                    isEditingFocused = true
                }
            } else {
                Button {
                    onSelect()
                } label: {
                    HStack(spacing: 6) {
                        Color.clear
                            .frame(width: 20)

                        Text(displayFileName)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .contentShape(Rectangle())
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .background(isSelected && !isEditing ? Color.accentColor.opacity(0.12) : Color.clear)
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

    return List {
        Section("Documents") {
            FileTreeContentView(
                node: root,
                selectedEntryId: .constant(nil),
                editingEntryId: .constant(nil),
                editingFileName: .constant(""),
                onSelectFile: { _ in },
                onRename: { _ in },
                onCommitRename: { _, _ in },
                onCancelRename: {},
                onDelete: { _ in },
                onCreateFile: { _ in },
                onCreateFolder: { _ in },
                onDeleteFolder: { _ in }
            )
        }
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 400)
}
