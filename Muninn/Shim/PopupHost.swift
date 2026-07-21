import Foundation
import WebKit
import AppKit

/// E7-minimal-popup: renders Proton's vendored `popup.html`/`popup.js` in a WKWebView so
/// the real "Sign in" runs the auth-fork INITIATION (writes `storage.session["f"+state]`
/// and opens the fork URL) — the step our onboarding path skipped, and the daily-driver
/// sign-in UX.
///
/// Unlike web content (where the shim is confined to an isolated world and MAIN is kept
/// clean — S2), the popup is a TRUSTED extension page served from `muninn-ext://<id>`, so
/// the `chrome`/`browser` shim is installed directly in its MAIN world. Served via the
/// existing `ExtensionSchemeHandler`; wired to the `MessageBroker` as the `popup` context.
@MainActor
final class PopupHost: NSObject {
    let broker: MessageBroker
    private(set) var webView: WKWebView!
    private var bridge: PopupBridge!
    private var window: NSWindow?

    private(set) var events: [[String: Any]] = []
    func note(_ kind: String, _ info: [String: Any] = [:]) {
        var e: [String: Any] = ["kind": kind]; e.merge(info) { a, _ in a }; events.append(e)
    }

    init(broker: MessageBroker) {
        self.broker = broker
        super.init()

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(ExtensionSchemeHandler(), forURLScheme: PassBundle.scheme)
        let ucc = config.userContentController

        // Trusted extension page → shim in the MAIN world (.page), document_start, so
        // chrome/browser exist before popup.js runs.
        if let manifestData = try? JSONSerialization.data(withJSONObject: PassBundle.manifest),
           let manifestJSON = String(data: manifestData, encoding: .utf8) {
            let boot = "globalThis.__MUNINN = { id: \"\(PassBundle.canonicalID)\", manifest: \(manifestJSON) };"
            ucc.addUserScript(WKUserScript(source: boot, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        }
        if let poly = Self.resource("content-polyfill", "js") {
            ucc.addUserScript(WKUserScript(source: poly, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        }

        // content-polyfill talks to `webkit.messageHandlers.brokerIsolated`; register that
        // name for the MAIN world of THIS (trusted) popup webview only.
        let bridge = PopupBridge(host: self)
        ucc.addScriptMessageHandler(bridge, contentWorld: .page, name: "brokerIsolated")
        self.bridge = bridge

        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 360, height: 600), configuration: config)
        self.webView.navigationDelegate = self
        if ProcessInfo.processInfo.environment["MUNINN_E6_GATE"] != nil, #available(macOS 13.3, *) {
            self.webView.isInspectable = true
        }
        // The popup is a push context (background→popup events / responses).
        broker.registerContext("popup", webView: webView, world: .page)
    }

    /// Load the vendored popup page.
    func load() {
        webView.load(URLRequest(url: URL(string: "\(PassBundle.scheme)://\(PassBundle.canonicalID)/popup.html")!))
    }

    /// Show the popup in a small panel (gate/daily use). Warn Calvin before calling in a
    /// GUI session (ground rule 2).
    func present() {
        let w = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "Proton Pass"
        w.contentView = webView
        w.center()
        w.makeKeyAndOrderFront(nil)
        self.window = w
    }

    func stop() {
        broker.unregisterContext("popup")
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.configuration.userContentController.removeAllUserScripts()
        window?.orderOut(nil); window = nil
    }

    private static func resource(_ name: String, _ ext: String) -> String? {
        guard let u = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: u, encoding: .utf8)
    }
}

extension PopupHost: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        note("didFinish", ["url": webView.url?.absoluteString ?? ""])
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        note("didFail", ["error": String(describing: error)])
    }
}

/// Routes the popup's MAIN-world broker calls to the native `MessageBroker` (mirrors the
/// isolated-world bridge, but for the trusted popup context). `runtime.sendMessage` reaches
/// `background.js`'s `onMessage` via the cross-context bus.
@MainActor
private final class PopupBridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var host: PopupHost?
    init(host: PopupHost) { self.host = host }

    func userContentController(_ ucc: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let host, let env = message.body as? [String: Any] else { return (nil, "bad envelope") }
        let ns = env["ns"] as? String
        let args = env["args"] as? [Any] ?? []
        if ns == "__audit", let d = args.first as? [String: Any] {
            host.broker.record(ns: (d["ns"] as? String) ?? "?", member: (d["member"] as? String) ?? "?",
                               kind: (d["kind"] as? String) ?? "call")
            return (NSNull(), nil)
        }
        if ns == "__respond", let id = args.first as? String {
            host.broker.resolveResponse(id: id, result: args.count > 1 ? args[1] : nil)
            return (NSNull(), nil)
        }
        // Popup → background internal messaging (extension context → onMessage).
        if ns == "runtime", (env["method"] as? String) == "sendMessage" {
            let result = await host.broker.routeSendMessageToHost(args.first, senderURL: host.webView?.url?.absoluteString)
            return (result, nil)
        }
        // Cross-context ports (popup ⇄ background) — the popup drives its UI over these.
        if ns == "__port" {
            let m = env["method"] as? String
            let portId = args.first as? String ?? ""
            switch m {
            case "connect": host.broker.portConnect(portId: portId, name: (args.count > 1 ? args[1] as? String : nil) ?? "",
                                                     from: "popup", senderURL: host.webView?.url?.absoluteString)
            case "message": host.broker.portMessageFromClient(portId: portId, message: args.count > 1 ? args[1] : nil)
            case "disconnect": host.broker.portDisconnect(portId: portId, origin: "client")
            default: break
            }
            return (NSNull(), nil)
        }
        do { return (try host.broker.handle(env), nil) }
        catch { return (nil, String(describing: error)) }
    }
}
