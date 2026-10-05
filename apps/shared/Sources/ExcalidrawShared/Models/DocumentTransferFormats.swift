import SwiftUI
import UniformTypeIdentifiers

public enum DocumentTransferFormats {
    public static var importTypes: [UTType] {
        [UTType.json, .png, .svg, .xml] + ["excalidraw", "mindmap", "xmind", "mm", "opml"].compactMap { UTType(filenameExtension: $0) }
    }
    public static func exportType(_ format: String) -> UTType? {
        switch format {
        case "png": return .png
        case "svg": return .svg
        case "json": return .json
        case "html": return .html
        case "mindmap", "xmind", "mm", "opml": return UTType(filenameExtension: format) ?? .data
        default: return nil
        }
    }
}

public struct DocumentExportMenu: View {
    private let mindMap: Bool
    private let export: (String) -> Void
    public init(mindMap: Bool, export: @escaping (String) -> Void) { self.mindMap = mindMap; self.export = export }
    public var body: some View {
        Menu {
            Button("导出为 HTML") { export("html") }
            Button("导出为 PNG") { export("png") }
            Button("导出为 SVG") { export("svg") }
            if mindMap {
                Divider()
                Button("思维导图（.mindmap）") { export("mindmap") }
                Button("XMind（.xmind）") { export("xmind") }
                Button("FreeMind / Freeplane（.mm）") { export("mm") }
                Button("OPML（.opml）") { export("opml") }
            } else {
                Button("导出为 JSON") { export("json") }
            }
        } label: { Label("导出", systemImage: "square.and.arrow.up") }
    }
}
