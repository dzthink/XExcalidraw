// swiftc -O benchmark_webkit.swift -o /private/tmp/siye-webkit-perf
// Usage: siye-webkit-perf http://127.0.0.1:18765/tests/performance.html output.json
import AppKit
import WebKit

final class PerformanceRunner: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    func start() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "performanceResult")
        configuration.userContentController.add(self, name: "performanceProgress")
        configuration.userContentController.add(self, name: "performanceSnapshot")
        configuration.userContentController.add(self, name: "performanceMouse")
        configuration.userContentController.addUserScript(WKUserScript(source: "window.addEventListener('error', e => window.webkit.messageHandlers.performanceResult.postMessage({error: e.message})); window.addEventListener('unhandledrejection', e => window.webkit.messageHandlers.performanceResult.postMessage({error: String(e.reason)}));", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 900), configuration: configuration)
        webView.navigationDelegate = self
        window = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Siye synthetic WebKit performance audit"
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        webView.load(URLRequest(url: URL(string: CommandLine.arguments[1])!))
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { self.finish(["error": "Benchmark timed out"], code: 1) }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "performanceMouse", let events = message.body as? [[String: Any]] {
            let types: [String: NSEvent.EventType] = ["leftDown": .leftMouseDown, "leftDrag": .leftMouseDragged, "leftUp": .leftMouseUp, "rightDown": .rightMouseDown, "rightDrag": .rightMouseDragged, "rightUp": .rightMouseUp]
            for (index, item) in events.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) {
                    if let name = item["type"] as? String, let type = types[name], let x = item["x"] as? Double, let y = item["y"] as? Double,
                       let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: self.webView.bounds.height - y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: self.window.windowNumber, context: nil, eventNumber: index, clickCount: 1, pressure: 1) {
                        // Send only to this synthetic test window; do not move the system pointer.
                        self.window.sendEvent(event)
                    }
                    if index == events.count - 1 {
                        self.webView.evaluateJavaScript("window.dispatchEvent(new Event('performance-mouse-finished'))", completionHandler: nil)
                    }
                }
            }
            return
        }
        if message.name == "performanceSnapshot", let name = message.body as? String {
            webView.takeSnapshot(with: nil) { image, _ in
                if let data = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]).deletingLastPathComponent().appendingPathComponent("siye-regression-\(name).png"))
                }
                self.webView.evaluateJavaScript("window.dispatchEvent(new Event('performance-snapshot-finished'))", completionHandler: nil)
            }
            return
        }
        if message.name == "performanceProgress" { print(message.body); fflush(stdout); return }
        finish(message.body, code: (message.body as? [String: Any])?["error"] == nil ? 0 : 1)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(["error": error.localizedDescription], code: 1)
    }
    func finish(_ result: Any, code: Int32) {
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
            print(String(decoding: data, as: UTF8.self))
        } catch { print(error) }
        exit(code)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let runner = PerformanceRunner()
runner.start()
app.run()
