#if canImport(WebKit)
import WebKit
import XCTest
@testable import ExcalidrawShared

final class WeakScriptMessageHandlerTests: XCTestCase {
    private final class Handler: NSObject, WKScriptMessageHandler {
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
    }

    func testContentControllerDoesNotKeepCanvasOwnerAlive() {
        let controller = WKUserContentController()
        var owner: Handler? = Handler()
        weak var weakOwner = owner
        controller.add(WeakScriptMessageHandler(owner!), name: "bridge")
        owner = nil
        XCTAssertNil(weakOwner)
        controller.removeScriptMessageHandler(forName: "bridge")
    }
}
#endif
