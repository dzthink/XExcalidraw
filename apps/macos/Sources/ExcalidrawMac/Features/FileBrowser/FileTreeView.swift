import SwiftUI
import ExcalidrawShared

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
                        .font(.callout)
                    Text(node.name)
                        .font(.callout)
                    Spacer()
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
                .padding(.leading, CGFloat(level * 12))
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
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .foregroundStyle(Color.accentColor)
                    .font(.callout)
                Text(entry.fileName)
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
            .padding(.leading, CGFloat(level * 12 + 20))
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(4)
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
