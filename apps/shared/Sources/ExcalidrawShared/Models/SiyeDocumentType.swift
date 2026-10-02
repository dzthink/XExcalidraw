import Foundation

public enum SiyeDocumentType: String, CaseIterable {
    case excalidraw
    case mindmap

    public init?(fileName: String) {
        let name = fileName.lowercased()
        if name.hasSuffix(".mindmap") {
            self = .mindmap
        } else if name.hasSuffix(".excalidraw") || name.hasSuffix(".excalidraw.json") {
            self = .excalidraw
        } else {
            return nil
        }
    }

    public var fileExtension: String { ".\(rawValue)" }

    public var blankScene: [String: Any] {
        switch self {
        case .excalidraw: return ["elements": [], "appState": [:]]
        case .mindmap:
            return [
                "format": "siye-mindmap", "version": 2,
                "nodeData": ["id": UUID().uuidString, "content": ["type": "doc", "content": [["type": "paragraph", "content": [["type": "text", "text": "中心主题"]]]]], "note": "", "expanded": true, "children": []],
                "settings": ["layout": "side", "palette": "gray", "noteDisplay": "all"],
                "views": ["mode": "outline", "outlineScroll": 0, "map": ["scale": 1, "x": 0, "y": 0], "focusId": NSNull(), "selectedIds": []]
            ]
        }
    }

    public static func displayName(from fileName: String) -> String {
        for suffix in [".excalidraw.json", ".excalidraw", ".mindmap"] where fileName.lowercased().hasSuffix(suffix) {
            return String(fileName.dropLast(suffix.count))
        }
        return fileName
    }
}
