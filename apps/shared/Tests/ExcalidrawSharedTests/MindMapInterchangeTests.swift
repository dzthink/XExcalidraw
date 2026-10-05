import XCTest
@testable import ExcalidrawShared

final class MindMapInterchangeTests: XCTestCase {
    private func root(_ text: String, ext: String) throws -> [String: Any] {
        let document = try MindMapInterchange.decode(Data(text.utf8), extension: ext, title: "文件名")
        return try XCTUnwrap(document["nodeData"] as? [String: Any])
    }
    private func title(_ node: [String: Any]) -> String {
        let doc = node["content"] as? [String: Any]
        let paragraphs = doc?["content"] as? [[String: Any]]
        let texts = paragraphs?.first?["content"] as? [[String: Any]]
        return texts?.first?["text"] as? String ?? ""
    }
    func testFreeMindImportsTextNotesAndFoldedChildren() throws {
        let tree = try root("<map version=\"1.0.1\"><node TEXT=\"中文 &amp; &lt;主题&gt;\" FOLDED=\"true\"><richcontent TYPE=\"NOTE\"><html><body><p>备注</p></body></html></richcontent><node TEXT=\"子主题\"/></node></map>", ext: "mm")
        XCTAssertEqual(title(tree), "中文 & <主题>")
        XCTAssertEqual(tree["note"] as? String, "备注")
        XCTAssertEqual(tree["expanded"] as? Bool, false)
        XCTAssertEqual((tree["children"] as? [[String: Any]])?.count, 1)
    }
    func testFreeMindRichContentKeepsMixedTextOrderAndParagraphBreaks() throws {
        let tree = try root("<map><node><richcontent TYPE=\"NODE\"><html><body><p>前<b>加粗</b>后</p><p>第二段</p></body></html></richcontent></node></map>", ext: "mm")
        XCTAssertEqual(title(tree), "前加粗后\n第二段")
    }
    func testOPMLPreservesMultipleRoots() throws {
        let tree = try root("<opml version=\"2.0\"><body><outline text=\"一\" _note=\"备注\"><outline text=\"子\"/></outline><outline text=\"二\"/></body></opml>", ext: "opml")
        XCTAssertEqual(title(tree), "文件名")
        let children = try XCTUnwrap(tree["children"] as? [[String: Any]])
        XCTAssertEqual(children.map(title), ["一", "二"])
        XCTAssertEqual(children[0]["note"] as? String, "备注")
    }
    func testModernCompressedXMindKeepsEverySheetAndFloatingTopic() throws {
        let data = Data(base64Encoded: "UEsDBBQAAAAIAN2gRV1DKqpYrwAAAAABAAAMAAAAY29udGVudC5qc29ui65WKsrPLwnJL8hMVrJSqFYqySzJSQWylJ7sWPt0f7OCmoLNkx27Xy6aYaeko6CUVJSYl5wBkk7Lz0lJTQGJ5eWXpBaD9RbkJGbmgVnJ+XklqXklIIVPl7Q/27wiJu/5mjVPdvW8WNijVFsL1JWckZmTUpQKUZ5YUpKYnAE0zkohGskJT9dOgNitVBsL1JKSilXVs63rnnatgCusBRmP01cQVzzds+Dp7H1Ah8QCAFBLAQIUAxQAAAAIAN2gRV1DKqpYrwAAAAABAAAMAAAAAAAAAAAAAACAAQAAAABjb250ZW50Lmpzb25QSwUGAAAAAAEAAQA6AAAA2QAAAAAA")!
        let document = try MindMapInterchange.decode(data, extension: "xmind", title: "文件名")
        let tree = try XCTUnwrap(document["nodeData"] as? [String: Any])
        let sheets = try XCTUnwrap(tree["children"] as? [[String: Any]])
        XCTAssertEqual(sheets.map(title), ["中心 & <主题>", "第二张图"])
        XCTAssertEqual(sheets[0]["expanded"] as? Bool, false)
        XCTAssertEqual(sheets[0]["note"] as? String, "备注\n第二行")
        XCTAssertEqual((sheets[0]["children"] as? [[String: Any]])?.map(title), ["子主题", "浮动主题"])
        let end = data.count - 22
        let centralOffset = (0..<4).reduce(0) { $0 | Int(data[end + 16 + $1]) << ($1 * 8) }
        var corrupt = data; corrupt[centralOffset + 16] ^= 1
        XCTAssertThrowsError(try MindMapInterchange.decode(corrupt, extension: "xmind", title: "坏文件"))
    }
    func testLegacyCompressedXMind() throws {
        let data = Data(base64Encoded: "UEsDBBQAAAAIAN2gRV0h/VNOuQAAABABAAALAAAAY29udGVudC54bWxNkL0KwjAUhV+lZNeIY0jzLjGNNJDelvYKdXZQNzedRdClk0vBwZdpK76FrYk/0+We73IO5/IykdlIpYAaMCgTC0VIFjmwMjEQsYGyt8r8DZuOJ0TwItYaBcc0MyqY5RJUHJJ5aiMd9RQNWi26/fmx3TR11d5XnDqNQ4q6EDyz0oBoT+vueuHUbZx6qGJjo1yD9y8CXGY6JBJRqtgFDPonp612TX17Hg/fEOq5m70j/Vl+ma9A/z8gXlBLAQIUAxQAAAAIAN2gRV0h/VNOuQAAABABAAALAAAAAAAAAAAAAACAAQAAAABjb250ZW50LnhtbFBLBQYAAAAAAQABADkAAADiAAAAAAA=")!
        let doc = try MindMapInterchange.decode(data, extension: "xmind", title: "文件名")
        let tree = try XCTUnwrap(doc["nodeData"] as? [String: Any])
        XCTAssertEqual(title(tree), "旧版中心")
        XCTAssertEqual(tree["note"] as? String, "备注")
        XCTAssertEqual(tree["expanded"] as? Bool, false)
        XCTAssertEqual((tree["children"] as? [[String: Any]])?.map(title), ["子主题"])
    }
    func testStoredXMindExportFromWebCanBeImported() throws {
        let data = Data(base64Encoded: "UEsDBBQAAAgAAAAAIQCxHdWhkQEAAJEBAAAMAAAAY29udGVudC5qc29uW3siaWQiOiJhMmQyMGQ3Yy0yZDg0LTQ4MDctYTNkNi1iODk3NjAxZjkxYjMiLCJjbGFzcyI6InNoZWV0IiwidGl0bGUiOiLkuK3lv4MgJiA85Li76aKYPiIsInJvb3RUb3BpYyI6eyJpZCI6InJvb3QiLCJjbGFzcyI6InRvcGljIiwidGl0bGUiOiLkuK3lv4MgJiA85Li76aKYPiIsImJyYW5jaCI6ImZvbGRlZCIsIm5vdGVzIjp7InBsYWluIjp7ImNvbnRlbnQiOiLlpIfms6hcbuesrOS6jOihjCJ9fSwiY2hpbGRyZW4iOnsiYXR0YWNoZWQiOlt7ImlkIjoiY2hpbGQiLCJjbGFzcyI6InRvcGljIiwidGl0bGUiOiLlrZDkuLvpopgiLCJicmFuY2giOiJmb2xkZWQiLCJub3RlcyI6eyJwbGFpbiI6eyJjb250ZW50Ijoi5aSH5rOoXG7nrKzkuozooYwifX0sImNoaWxkcmVuIjp7ImF0dGFjaGVkIjpbXX19XX19fV1QSwMEFAAACAAAAAAhAKsNLeMrAAAAKwAAAA0AAABtZXRhZGF0YS5qc29ueyJjcmVhdG9yIjp7Im5hbWUiOiJTaXllIiwidmVyc2lvbiI6IjEuMCJ9fVBLAwQUAAAIAAAAACEAktq1AjcAAAA3AAAADQAAAG1hbmlmZXN0Lmpzb257ImZpbGUtZW50cmllcyI6eyJjb250ZW50Lmpzb24iOnt9LCJtZXRhZGF0YS5qc29uIjp7fX19UEsBAhQAFAAACAAAAAAhALEd1aGRAQAAkQEAAAwAAAAAAAAAAAAAAAAAAAAAAGNvbnRlbnQuanNvblBLAQIUABQAAAgAAAAAIQCrDS3jKwAAACsAAAANAAAAAAAAAAAAAAAAALsBAABtZXRhZGF0YS5qc29uUEsBAhQAFAAACAAAAAAhAJLatQI3AAAANwAAAA0AAAAAAAAAAAAAAAAAEQIAAG1hbmlmZXN0Lmpzb25QSwUGAAAAAAMAAwCwAAAAcwIAAAAA")!
        let doc = try MindMapInterchange.decode(data, extension: "xmind", title: "文件名")
        let tree = try XCTUnwrap(doc["nodeData"] as? [String: Any])
        XCTAssertEqual(title(tree), "中心 & <主题>")
        XCTAssertEqual(tree["note"] as? String, "备注\n第二行")
        XCTAssertEqual((tree["children"] as? [[String: Any]])?.map(title), ["子主题"])
    }
    func testRejectsMalformedOrUnrelatedInput() {
        for (text, ext) in [("<map><node></map>", "mm"), ("<html><node TEXT=\"x\"/></html>", "mm"), ("<opml><body/></opml>", "opml"), ("not a ZIP", "xmind"), ("{}", "mindmap")] {
            XCTAssertThrowsError(try root(text, ext: ext))
        }
    }
}
