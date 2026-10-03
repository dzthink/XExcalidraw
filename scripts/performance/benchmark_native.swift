// Compile with the production file-entry, JSON index-store and file-tree sources.
// Pass an output directory and optionally the synthetic document fixture directory.
import Foundation
import Combine

@main
struct PerformanceAudit {
    static func measure(_ run: () throws -> Void, samples: Int = 30) rethrows -> [String: Double] {
        for _ in 0..<5 { try run() }
        var values: [Double] = []
        for _ in 0..<samples {
            let start = DispatchTime.now().uptimeNanoseconds
            try run()
            values.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        values.sort()
        return ["p50_ms": values[Int(ceil(Double(samples) * 0.5)) - 1], "p95_ms": values[Int(ceil(Double(samples) * 0.95)) - 1]]
    }

    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let folderID = UUID()
        var results: [[String: Any]] = []
        for count in [100, 1000, 10000] {
            let entries = (0..<count).map { index in
                ExcalidrawFileEntry(folderId: folderID, relativePath: "folder-\(index / 100)/file-\(index).mindmap", fileName: "file-\(index).mindmap", fileURL: output.appendingPathComponent("folder-\(index / 100)/file-\(index).mindmap"), modifiedAt: Date(timeIntervalSince1970: 1_790_000_000), fileSize: 1000)
            }
            let indexStore = ExcalidrawJSONFileIndexStore(fileURL: output.appendingPathComponent("index.json"))
            let persist = try measure { try indexStore.saveEntries(entries) }
            let tree = measure { _ = FileTreeBuilder.buildTree(entries: entries, folderName: "Fixture") }
            results.append(["entries": count, "persist_index": persist, "build_tree_without_disk_enumeration": tree])
        }
        if CommandLine.arguments.count > 2 {
            let fixture = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            for count in [100, 500, 1000, 5000] {
                let data = try Data(contentsOf: fixture.appendingPathComponent("document-\(count).json"))
                let json = try JSONSerialization.jsonObject(with: data)
                let envelope = try JSONSerialization.data(withJSONObject: ["version": "1.0", "type": "saveScene", "payload": ["docId": "fixture.mindmap", "sceneJson": String(decoding: data, as: UTF8.self)]])
                let inbound = try measure {
                    let parsed = try JSONSerialization.jsonObject(with: envelope) as! [String: Any]
                    let payload = parsed["payload"] as! [String: Any]
                    let scene = try JSONSerialization.jsonObject(with: Data((payload["sceneJson"] as! String).utf8))
                    _ = JSONSerialization.isValidJSONObject(scene)
                }
                let outbound = try measure {
                    let serialized = try JSONSerialization.data(withJSONObject: ["version": "1.0", "type": "loadScene", "payload": ["docId": "fixture.mindmap", "sceneJson": json]])
                    let string = String(decoding: serialized, as: UTF8.self)
                    _ = string.debugDescription
                }
                results.append(["nodes": count, "inbound_parse_and_validate": inbound, "outbound_serialize_and_escape": outbound])
            }
        }
        let data = try JSONSerialization.data(withJSONObject: ["optimization": "swiftc -O", "samples": 30, "warmup": 5, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("native-results.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
