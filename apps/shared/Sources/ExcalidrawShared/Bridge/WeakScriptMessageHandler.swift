#if canImport(WebKit)
import WebKit

/// WKUserContentController retains handlers; the web view must not retain its owner.
public final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    public init(_ target: WKScriptMessageHandler) {
        self.target = target
        super.init()
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
#endif
