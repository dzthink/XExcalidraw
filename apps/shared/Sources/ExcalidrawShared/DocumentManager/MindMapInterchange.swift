import Foundation
import Compression

/// Converts interchange files to the editable Siye tree. External styling is not imported.
public enum MindMapInterchange {
    public static let extensions = ["mindmap", "xmind", "mm", "opml"]

    public static func decode(_ data: Data, extension ext: String, title: String) throws -> [String: Any] {
        guard data.count <= 64 * 1024 * 1024 else { throw DocumentManagerError.invalidImportData }
        var roots: [[String: Any]] = []
        switch ext.lowercased() {
        case "mindmap":
            guard let doc = try JSONSerialization.jsonObject(with: data) as? [String: Any], doc["nodeData"] is [String: Any] else { throw DocumentManagerError.invalidImportData }
            return doc
        case "xmind":
            let files = try ZIPContent.read(data)
            if let json = files["content.json"] {
                guard let sheets = try JSONSerialization.jsonObject(with: json) as? [[String: Any]], !sheets.isEmpty else { throw DocumentManagerError.invalidImportData }
                roots = try sheets.map { sheet in
                    guard let topic = sheet["rootTopic"] as? [String: Any] else { throw DocumentManagerError.invalidImportData }
                    return try xmindNode(topic, depth: 0)
                }
            } else if let xml = files["content.xml"] {
                let tree = try XMLTree.read(xml)
                roots = tree.children.filter { $0.name == "sheet" }.compactMap { $0.children.first { $0.name == "topic" } }.map { xmlNode($0, kind: "topic") }
            } else { throw DocumentManagerError.invalidImportData }
        case "mm":
            let tree = try XMLTree.read(data)
            guard tree.name == "map" else { throw DocumentManagerError.invalidImportData }
            roots = tree.children.filter { $0.name == "node" }.map { xmlNode($0, kind: "node") }
        case "opml":
            let tree = try XMLTree.read(data)
            guard tree.name == "opml", let body = tree.children.first(where: { $0.name == "body" }) else { throw DocumentManagerError.invalidImportData }
            roots = body.children.filter { $0.name == "outline" }.map { xmlNode($0, kind: "outline") }
        default: throw DocumentManagerError.unsupportedImportType
        }
        guard !roots.isEmpty else { throw DocumentManagerError.invalidImportData }
        var doc = SiyeDocumentType.mindmap.blankScene
        let root = roots.count == 1 ? roots[0] : node(title, children: roots)
        func checkDepth(_ tree: [String: Any], depth: Int) throws {
            guard depth <= 100 else { throw DocumentManagerError.invalidImportData }
            for child in tree["children"] as? [[String: Any]] ?? [] { try checkDepth(child, depth: depth + 1) }
        }
        try checkDepth(root, depth: 0)
        doc["nodeData"] = root
        return doc
    }

    private static func node(_ text: String, note: String = "", expanded: Bool = true, children: [[String: Any]] = []) -> [String: Any] {
        ["id": UUID().uuidString, "content": ["type": "doc", "content": [["type": "paragraph", "content": text.isEmpty ? [] : [["type": "text", "text": text]]]]], "note": note, "expanded": expanded, "children": children]
    }

    private static func xmindNode(_ topic: [String: Any], depth: Int) throws -> [String: Any] {
        guard depth <= 100, let title = topic["title"] as? String else { throw DocumentManagerError.invalidImportData }
        let groups = topic["children"] as? [String: Any] ?? [:]
        let children = (groups["attached"] as? [[String: Any]] ?? []) + (groups["detached"] as? [[String: Any]] ?? [])
        let notes = topic["notes"] as? [String: Any]
        let plain = notes?["plain"] as? [String: Any]
        return node(title, note: plain?["content"] as? String ?? "", expanded: topic["branch"] as? String != "folded", children: try children.map { try xmindNode($0, depth: depth + 1) })
    }

    private static func xmlNode(_ tree: XMLTree.Element, kind: String) -> [String: Any] {
        let text: String
        let note: String
        let children: [XMLTree.Element]
        if kind == "node" {
            text = tree.attributes["TEXT"] ?? tree.children.first(where: { $0.name == "richcontent" && $0.attributes["TYPE"] == "NODE" })?.allText ?? ""
            note = tree.children.first(where: { $0.name == "richcontent" && $0.attributes["TYPE"] == "NOTE" })?.allText ?? ""
            children = tree.children.filter { $0.name == kind }
        } else if kind == "outline" {
            text = tree.attributes["text"] ?? tree.attributes["title"] ?? ""
            note = tree.attributes["_note"] ?? ""
            children = tree.children.filter { $0.name == kind }
        } else {
            text = tree.children.first(where: { $0.name == "title" })?.allText ?? ""
            note = tree.children.first(where: { $0.name == "notes" })?.allText ?? ""
            children = tree.children.first(where: { $0.name == "children" })?.children.filter { $0.name == "topics" && ["attached", "detached"].contains($0.attributes["type"] ?? "") }.flatMap { $0.children.filter { $0.name == "topic" } } ?? []
        }
        return node(text, note: note, expanded: tree.attributes["FOLDED"] != "true" && tree.attributes["branch"] != "folded", children: children.map { xmlNode($0, kind: kind) })
    }
}

private final class XMLTree: NSObject, XMLParserDelegate {
    final class Element {
        let name: String
        let attributes: [String: String]
        var text = ""
        var children: [Element] = []
        var allText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        init(_ name: String, _ attributes: [String: String]) { self.name = name; self.attributes = attributes }
    }
    var stack: [Element] = []
    var root: Element?
    static func read(_ data: Data) throws -> Element {
        let delegate = XMLTree()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { throw DocumentManagerError.invalidImportData }
        return root
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        guard stack.count < 256 else { parser.abortParsing(); return }
        let element = Element(elementName, attributeDict)
        if let parent = stack.last { parent.children.append(element) } else { root = element }
        stack.append(element)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { for element in stack { element.text += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = stack.popLast()
        if ["p", "div", "br", "li"].contains(elementName) { for element in stack { element.text += "\n" } }
    }
}

private enum ZIPContent {
    static func read(_ data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        func value(_ offset: Int, _ count: Int) throws -> Int {
            guard offset >= 0, offset + count <= bytes.count else { throw DocumentManagerError.invalidImportData }
            return (0..<count).reduce(0) { $0 | Int(bytes[offset + $1]) << ($1 * 8) }
        }
        guard bytes.count >= 22 else { throw DocumentManagerError.invalidImportData }
        var endOffset: Int?
        for candidate in stride(from: bytes.count - 22, through: max(0, bytes.count - 65557), by: -1) {
            if try value(candidate, 4) == 0x06054b50 {
                let commentSize = try value(candidate + 20, 2)
                if candidate + 22 + commentSize == bytes.count { endOffset = candidate; break }
            }
        }
        guard let end = endOffset else { throw DocumentManagerError.invalidImportData }
        guard try value(end + 4, 2) == 0, try value(end + 6, 2) == 0 else { throw DocumentManagerError.invalidImportData }
        var offset = try value(end + 16, 4)
        var result: [String: Data] = [:]
        for _ in 0..<(try value(end + 10, 2)) {
            guard try value(offset, 4) == 0x02014b50 else { throw DocumentManagerError.invalidImportData }
            let length = try value(offset + 28, 2)
            guard offset + 46 + length <= bytes.count else { throw DocumentManagerError.invalidImportData }
            let name = String(bytes: bytes[(offset + 46)..<(offset + 46 + length)], encoding: .utf8) ?? ""
            if ["content.json", "content.xml"].contains(name) {
                let size = try value(offset + 20, 4), unpacked = try value(offset + 24, 4)
                guard unpacked <= 32 * 1024 * 1024, try value(offset + 8, 2) & 1 == 0 else { throw DocumentManagerError.invalidImportData }
                let local = try value(offset + 42, 4)
                guard try value(local, 4) == 0x04034b50 else { throw DocumentManagerError.invalidImportData }
                let localNameLength = try value(local + 26, 2)
                let extraLength = try value(local + 28, 2)
                let start: Int = local + 30 + localNameLength + extraLength
                guard start + size <= bytes.count else { throw DocumentManagerError.invalidImportData }
                let compressed = Array(bytes[start..<(start + size)])
                let method = try value(offset + 10, 2)
                let output: Data
                if method == 0 { output = Data(compressed) }
                else if method == 8 {
                    guard !compressed.isEmpty else { throw DocumentManagerError.invalidImportData }
                    var destination = [UInt8](repeating: 0, count: max(1, unpacked + 1))
                    let count = compressed.withUnsafeBytes { source in
                        destination.withUnsafeMutableBytes { target in
                            compression_decode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, target.count, source.bindMemory(to: UInt8.self).baseAddress!, source.count, nil, COMPRESSION_ZLIB)
                        }
                    }
                    guard count == unpacked else { throw DocumentManagerError.invalidImportData }
                    output = Data(destination.prefix(count))
                } else { throw DocumentManagerError.invalidImportData }
                guard output.count == unpacked else { throw DocumentManagerError.invalidImportData }
                var crc: UInt32 = 0xffffffff
                for byte in output { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) } }
                guard Int(crc ^ 0xffffffff) == (try value(offset + 16, 4)) else { throw DocumentManagerError.invalidImportData }
                result[name] = output
            }
            let extraSize = try value(offset + 30, 2)
            let commentSize = try value(offset + 32, 2)
            offset += 46 + length + extraSize + commentSize
        }
        return result
    }
}
