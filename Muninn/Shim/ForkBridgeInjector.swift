import Foundation
import WebKit

/// Minimal content-world injection for the S2 spike (NOT the full FR-9/E5
/// InjectionCoordinator). Owns a page WKWebView whose isolated `WKContentWorld`
/// carries the content shim + (on `*.proton.me`) Proton's `fork.js`, wired to
/// the MessageBroker as a second context. The page MAIN world gets nothing —
/// that isolation is the load-bearing S2 guarantee (ADR-007).
///
/// E5 replaces this with the general injector + frame registry; the seam is the
/// `isolatedWorld` + broker registration.
@MainActor
final class ForkBridgeInjector: NSObject {
    static let isolatedWorldName = "MuninnShim"
    static let forkMatchHostSuffix = "account.proton.me"

    let broker: MessageBroker
    private(set) var webView: WKWebView!
    private let isolatedWorld: WKContentWorld
    private var bridge: IsolatedBridge!

    /// Observations for the S2 spike artifact.
    private(set) var events: [[String: Any]] = []
    func note(_ kind: String, _ info: [String: Any] = [:]) {
        var e: [String: Any] = ["kind": kind]; e.merge(info) { a, _ in a }; events.append(e)
    }

    init(broker: MessageBroker) {
        self.broker = broker
        self.isolatedWorld = WKContentWorld.world(name: Self.isolatedWorldName)
        super.init()

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(ExtensionSchemeHandler(), forURLScheme: PassBundle.scheme)

        // Content shim → isolated world only, at document start, MAIN FRAME only
        // (the fork bridge is a main-frame concern; keeps the broker-reachable
        // surface off cross-origin subframes — isolation holds either way).
        if let shim = Self.resource("content-shim", "js") {
            let us = WKUserScript(source: shim, injectionTime: .atDocumentStart,
                                  forMainFrameOnly: true, in: isolatedWorld)
            config.userContentController.addUserScript(us)
        }

        // Broker handler registered ONLY for the isolated world — the page MAIN
        // world cannot reach webkit.messageHandlers.brokerIsolated.
        let bridge = IsolatedBridge(injector: self)
        config.userContentController.addScriptMessageHandler(
            bridge, contentWorld: isolatedWorld, name: "brokerIsolated")
        self.bridge = bridge

        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.navigationDelegate = self
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }

    /// Lifecycle symmetry with BackgroundHost (this owns a live networking WKWebView).
    func stop() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.configuration.userContentController.removeAllUserScripts()
    }

    /// Does this host match the vendored manifest's fork.js pattern
    /// (`https://account.proton.me/*`)? Chrome match-pattern host semantics are
    /// an **exact** host match (no subdomains). Case-folded defensively. Pure,
    /// so the scoping is unit-testable.
    static func matchesForkHost(_ host: String) -> Bool {
        host.lowercased() == forkMatchHostSuffix
    }

    // MARK: - S2 probes

    /// Last probe error (diagnostic), surfaced to tests instead of being swallowed.
    private(set) var lastProbeError: String = ""

    /// `typeof window.chrome` / `window.browser` in the PAGE MAIN world (must be undefined).
    /// Uses callAsyncJavaScript (explicit return) — the reliable API for retrieving
    /// values from a specific content world.
    func probeMainWorld() async -> (chrome: String, browser: String) {
        do {
            let r = try await webView.callAsyncJavaScript(
                "return JSON.stringify([typeof window.chrome, typeof window.browser])",
                arguments: [:], in: nil, contentWorld: .page)
            if let s = r as? String, let d = s.data(using: .utf8),
               let a = try? JSONSerialization.jsonObject(with: d) as? [String], a.count == 2 {
                return (a[0], a[1])
            }
            lastProbeError = "main: unexpected result \(type(of: r)) = \(r)"
        } catch { lastProbeError = "main: \(error)" }
        return ("?", "?")
    }

    /// The isolated world DOES expose the shim.
    func probeIsolatedWorld() async -> Bool {
        do {
            let r = try await webView.callAsyncJavaScript(
                "return (typeof globalThis.chrome === 'object' && !!globalThis.chrome.runtime)",
                arguments: [:], in: nil, contentWorld: isolatedWorld)
            return (r as? Bool) ?? (r as? NSNumber)?.boolValue ?? false
        } catch { lastProbeError = "isolated: \(error)"; return false }
    }

    private static func resource(_ name: String, _ ext: String) -> String? {
        guard let u = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: u, encoding: .utf8)
    }
}

extension ForkBridgeInjector: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let host = webView.url?.host ?? ""
        note("didFinish", ["host": host])
        // Inject fork.js only on the manifest's match host — WKUserScript can't
        // match-pattern, so we gate injection here (this-change scoping; E5 does
        // it properly via the frame registry).
        guard Self.matchesForkHost(host) else { return }
        guard let root = PassBundle.rootURL,
              let fork = try? String(contentsOf: root.appendingPathComponent("fork.js"), encoding: .utf8) else {
            note("forkMissing"); return
        }
        webView.evaluateJavaScript(fork, in: nil, in: isolatedWorld) { [weak self] result in
            // Distinct kind on failure so audit readers can't miscount a failed
            // injection as a success.
            if case .failure(let e) = result { self?.note("forkFailed", ["error": String(describing: e)]) }
            else { self?.note("forkInjected") }
        }
    }
}

/// Routes the isolated world's broker calls to the native MessageBroker.
@MainActor
private final class IsolatedBridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var injector: ForkBridgeInjector?
    init(injector: ForkBridgeInjector) { self.injector = injector }

    func userContentController(_ ucc: WKUserContentController,
                              didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let injector, let env = message.body as? [String: Any] else { return (nil, "bad envelope") }
        do { return (try injector.broker.handle(env), nil) }
        catch { return (nil, String(describing: error)) }
    }
}
