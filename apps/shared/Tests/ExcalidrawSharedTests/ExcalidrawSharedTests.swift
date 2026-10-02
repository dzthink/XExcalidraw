import XCTest
@testable import ExcalidrawShared

final class ExcalidrawSharedTests: XCTestCase {
    func testDocumentExtensionsSelectTheCorrectEditor() {
        XCTAssertEqual(SiyeDocumentType(fileName: "idea.mindmap"), .mindmap)
        XCTAssertEqual(SiyeDocumentType(fileName: "drawing.excalidraw"), .excalidraw)
        XCTAssertEqual(SiyeDocumentType(fileName: "drawing.excalidraw.json"), .excalidraw)
        XCTAssertNil(SiyeDocumentType(fileName: "notes.json"))
        XCTAssertEqual(SiyeDocumentType.displayName(from: "idea.mindmap"), "idea")
    }

    func testBlankMindMapIsValidJSONWithRootNode() throws {
        let data = try JSONSerialization.data(withJSONObject: SiyeDocumentType.mindmap.blankScene)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let root = try XCTUnwrap(document["nodeData"] as? [String: Any])
        XCTAssertEqual(document["format"] as? String, "siye-mindmap")
        XCTAssertEqual(document["version"] as? Int, 2)
        let content = try XCTUnwrap(root["content"] as? [String: Any])
        XCTAssertEqual(content["type"] as? String, "doc")
        XCTAssertEqual(root["note"] as? String, "")
        XCTAssertEqual(root["expanded"] as? Bool, true)
        XCTAssertNotNil(root["id"] as? String)
    }
}
