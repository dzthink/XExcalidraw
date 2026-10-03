#if canImport(WebKit)
import Foundation
import WebKit

/// Reads bundled assets and document attachments without blocking WebKit's UI callbacks.
public final class BundleResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private let queue = DispatchQueue(label: "com.xexcalidraw.resources", qos: .userInitiated, attributes: .concurrent)
    private var documentURL: URL?
    private var repositoryURL: URL?
    private var tasks: [ObjectIdentifier: UUID] = [:]
    private let resourceURL: URL?

    public init(resourceURL: URL? = Bundle.main.resourceURL) {
        self.resourceURL = resourceURL
        super.init()
    }

    public func setAttachmentContext(documentURL: URL?, repositoryURL: URL?) {
        self.documentURL = documentURL
        self.repositoryURL = repositoryURL
    }

    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let id = ObjectIdentifier(urlSchemeTask), token = UUID()
        tasks[id] = token
        let documentURL = documentURL, repositoryURL = repositoryURL, resourceURL = resourceURL
        queue.async { [weak self] in
            let result = Result<(URL, Data), Error> {
                var path = (url.host ?? "") + url.path
                if path.hasPrefix("/") { path.removeFirst() }
                if path.isEmpty { path = "index.html" }
                let fileURL: URL
                if path == "mindmap-attachment" {
                    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    guard let documentURL, let repositoryURL,
                          query.first(where: { $0.name == "docId" })?.value == documentURL.path,
                          let relativePath = query.first(where: { $0.name == "path" })?.value,
                          let resolved = MindMapAttachmentStore.resolve(relativePath: relativePath, documentURL: documentURL, repositoryURL: repositoryURL) else {
                        throw URLError(.fileDoesNotExist)
                    }
                    fileURL = resolved
                } else {
                    guard let resourceURL else { throw URLError(.fileDoesNotExist) }
                    fileURL = resourceURL.appendingPathComponent(path).standardizedFileURL
                    guard fileURL.path.hasPrefix(resourceURL.standardizedFileURL.path + "/") else { throw URLError(.badURL) }
                }
                return (fileURL, try Data(contentsOf: fileURL))
            }
            DispatchQueue.main.async {
                guard let self, self.tasks[id] == token else { return }
                self.tasks.removeValue(forKey: id)
                switch result {
                case .success(let (fileURL, data)):
                    let mime = Self.mimeType(for: fileURL.pathExtension)
                    let encoding = mime.hasPrefix("text/") || ["application/javascript", "application/json"].contains(mime) ? "utf-8" : nil
                    urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: encoding))
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                case .failure(let error):
                    urlSchemeTask.didFailWithError(error)
                }
            }
        }
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html"
        case "js": return "application/javascript"
        case "css": return "text/css"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "json", "map": return "application/json"
        case "wasm": return "application/wasm"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        default: return "application/octet-stream"
        }
    }
}
#endif
