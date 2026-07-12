import Foundation
import WebKit
import UniformTypeIdentifiers

/// Minimal `muninn-ext://` scheme handler (ADR-006, this-change subset).
///
/// Serves files from the embedded PassBundle for the canonical extension
/// origin. This is deliberately NOT the full FR-8 web-accessible-resource
/// enforcement (page-embeddable iframes, S6 initiator identification) — that
/// is E4. The only consumer here is the background host itself, so "extension
/// origin only" is satisfied structurally: nothing else loads this scheme yet.
///
/// The Muninn-authored shim scripts (polyfill, boot, host page relay) live in
/// the app bundle's Resources and are also served under this origin so they are
/// same-origin with background.js (required for Worker importScripts).
final class ExtensionSchemeHandler: NSObject, WKURLSchemeHandler {

    /// Shim scripts served alongside the vendored bundle (Muninn-authored).
    private static let shimScripts: Set<String> = [
        "background-host.html", "background-host-page.js",
        "background-worker-boot.js", "shim-polyfill.js",
    ]

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              url.scheme == PassBundle.scheme,
              url.host == PassBundle.canonicalID else {
            fail(task, status: 404); return
        }

        var path = url.path
        if path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty { path = "background-host.html" }

        guard let data = load(path: path) else { fail(task, status: 404); return }

        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType(for: path),
                "Content-Length": String(data.count),
                // Same-origin only; no cross-origin embedding at this stage.
                "Access-Control-Allow-Origin": "null",
            ]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) { /* synchronous; nothing to cancel */ }

    // MARK: - file resolution

    private func load(path: String) -> Data? {
        // Muninn-authored shim scripts come from the app bundle Resources.
        if Self.shimScripts.contains(path) {
            if let u = Bundle.main.url(forResource: (path as NSString).deletingPathExtension,
                                       withExtension: (path as NSString).pathExtension) {
                return try? Data(contentsOf: u)
            }
        }
        // Everything else is a vendored bundle file. Guard against traversal —
        // compare with a trailing separator so a sibling dir sharing the prefix
        // (…/PassBundleEVIL) can't pass a bare hasPrefix(…/PassBundle) check.
        guard let root = PassBundle.rootURL else { return nil }
        let rootPath = root.standardizedFileURL.path
        let target = root.appendingPathComponent(path).standardizedFileURL
        guard target.path == rootPath || target.path.hasPrefix(rootPath + "/") else { return nil }
        return try? Data(contentsOf: target)
    }

    private func fail(_ task: WKURLSchemeTask, status: Int) {
        let url = task.request.url ?? URL(string: "\(PassBundle.scheme)://\(PassBundle.canonicalID)/")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        task.didReceive(response)
        task.didFinish()
    }

    private func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "js": return "text/javascript"
        case "html", "htm": return "text/html"
        case "json": return "application/json"
        case "wasm": return "application/wasm"
        case "css": return "text/css"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "csv": return "text/csv"
        default:
            if let t = UTType(filenameExtension: ext)?.preferredMIMEType { return t }
            return "application/octet-stream"
        }
    }
}
