import Foundation
import WebKit

/// FR-9 content-world injection coordinator (E5; grew out of the S2-spike
/// `ForkBridgeInjector`). Owns a page WKWebView whose isolated `WKContentWorld`
/// carries the full manifest injection set — bootstrap → content-polyfill
/// (`document_start`) → `orchestrator.js` (`document_end`, all frames) →
/// `webauthn.js` (MAIN, `document_start`) — plus, on `account.proton.me`, Proton's
/// `fork.js`; all wired to the MessageBroker as a second context, and feeding the
/// `FrameRegistry` from each frame's `WKScriptMessage.frameInfo`. The page MAIN
/// world gets nothing but `webauthn.js` (which references no `browser.*`) — that
/// isolation is the load-bearing S2 guarantee (ADR-007).
@MainActor
final class InjectionCoordinator: NSObject {
    static let isolatedWorldName = "MuninnShim"
    static let forkMatchHostSuffix = "account.proton.me"

    let broker: MessageBroker
    private(set) var webView: WKWebView!
    private let isolatedWorld: WKContentWorld
    private var bridge: IsolatedBridge!
    /// Broker context name (multi-tab: each tab is a distinct push context so native→page
    /// delivery targets the right tab). Default "page" for single-tab / tests.
    let contextName: String

    /// Optional gate on main-frame navigations — return `.cancel` to intercept (e.g. Peek
    /// opens a link from a pinned tab in a preview instead of navigating the tab). nil = allow.
    var onNavigationAction: ((WKNavigationAction) -> WKNavigationActionPolicy)?
    /// Called for `target="_blank"` / `window.open` (no WKWebView is created here — the host
    /// decides: a new tab, or a Peek from a pinned tab).
    var onCreateWebView: ((WKNavigationAction) -> Void)?
    /// Fired when this page starts/stops playing media (for the Mini Player).
    var onMediaState: ((Bool) -> Void)?
    /// Destination folder for downloads (the tab's profile download folder).
    var downloadFolder: (() -> URL)?
    /// Developer Mode: right-click "View Page Source" on this web view.
    var onViewSource: ((WKWebView) -> Void)?
    /// A finished download → recorded in the Library (destination, source URL).
    var onDownloadFinished: ((URL, URL?) -> Void)?
    /// Shields: whether JavaScript is allowed for a navigation (per-site script blocking).
    var onDecideJavaScript: ((URL?) -> Bool)?
    /// In-flight download → (destination, source) for recording on completion.
    private var downloadInfo: [ObjectIdentifier: (dest: URL, source: URL?)] = [:]

    /// Observations for the S2 spike artifact.
    private(set) var events: [[String: Any]] = []
    func note(_ kind: String, _ info: [String: Any] = [:]) {
        var e: [String: Any] = ["kind": kind]; e.merge(info) { a, _ in a }; events.append(e)
    }

    /// - Parameter injectContentScripts: inject the vendored orchestrator.js /
    ///   webauthn.js (default true). Unit tests of the bus/isolation pass false to
    ///   exercise the shim without orchestrator's page-side behavior.
    /// - Parameter configHook: called on the `WKWebViewConfiguration` after the
    ///   shim's user scripts / handlers are installed but BEFORE the `WKWebView` is
    ///   created (since `webView.configuration` is a copy, post-hoc mutation is
    ///   futile). Test-only seam: the boot-audit harness uses it to add
    ///   instrumentation user scripts and to keep an offscreen page process awake
    ///   (`inactiveSchedulingPolicy = .none`). Production passes nil.
    init(broker: MessageBroker, injectContentScripts: Bool = true,
         contextName: String = "page",
         dataStore: WKWebsiteDataStore? = nil,
         configHook: ((WKWebViewConfiguration) -> Void)? = nil) {
        self.broker = broker
        self.contextName = contextName
        self.isolatedWorld = WKContentWorld.world(name: Self.isolatedWorldName)
        super.init()

        let config = WKWebViewConfiguration()
        // Profiles: an isolated cookie/login/storage jar per profile (nil = the default store).
        if let dataStore { config.websiteDataStore = dataStore }
        config.setURLSchemeHandler(ExtensionSchemeHandler(), forURLScheme: PassBundle.scheme)
        // Developer Mode: enable WKPreferences developer extras so the in-app Web Inspector can
        // display (private KVC key; sets the backing ivar, so it can't raise for an unknown key).
        if AppSettings.developerMode { config.preferences.setValue(true, forKey: "developerExtrasEnabled") }

        // E5 general injection (FR-9), per the vendored manifest:
        //  isolated world, document_start: bootstrap (id+manifest) → content-polyfill
        //  isolated world, document_end, all frames: orchestrator.js
        //  MAIN world, document_start, all frames: webauthn.js (Proton's own; no browser.*)
        let ucc = config.userContentController
        func addUserScript(_ src: String, at time: WKUserScriptInjectionTime, world: WKContentWorld, allFrames: Bool) {
            ucc.addUserScript(WKUserScript(source: src, injectionTime: time, forMainFrameOnly: !allFrames, in: world))
        }
        // Bootstrap: expose id + manifest to the isolated world before the polyfill.
        if let manifestData = try? JSONSerialization.data(withJSONObject: PassBundle.manifest),
           let manifestJSON = String(data: manifestData, encoding: .utf8) {
            let boot = "globalThis.__MUNINN = { id: \"\(PassBundle.canonicalID)\", manifest: \(manifestJSON) };"
            addUserScript(boot, at: .atDocumentStart, world: isolatedWorld, allFrames: true)
        }
        if let poly = Self.resource("content-polyfill", "js") {
            addUserScript(poly, at: .atDocumentStart, world: isolatedWorld, allFrames: true)
        }
        // Media detection (Mini Player) — isolated world so the page can't spoof state.
        addUserScript(Self.mediaProbeJS, at: .atDocumentStart, world: isolatedWorld, allFrames: true)
        // externally_connectable bridge — MAIN world, document_start, all frames.
        // Self-gates on the manifest's externally_connectable hosts, so every other
        // origin's MAIN world stays clean (S2). Injected unconditionally (it's the
        // auth-fork detection path, independent of orchestrator).
        if let ecTemplate = Self.resource("externally-connectable", "js"),
           let hostsData = try? JSONSerialization.data(withJSONObject: PassBundle.externallyConnectableHosts),
           let hostsJSON = String(data: hostsData, encoding: .utf8) {
            let ec = ecTemplate
                .replacingOccurrences(of: "__EC_HOSTS_JSON__", with: hostsJSON)
                .replacingOccurrences(of: "__CANONICAL_ID__", with: PassBundle.canonicalID)
            addUserScript(ec, at: .atDocumentStart, world: .page, allFrames: true)
        }
        if injectContentScripts {
            // orchestrator.js — the general content script (all http(s) pages).
            if let root = PassBundle.rootURL,
               let orch = try? String(contentsOf: root.appendingPathComponent("orchestrator.js"), encoding: .utf8) {
                addUserScript(orch, at: .atDocumentEnd, world: isolatedWorld, allFrames: true)
            }
            // webauthn.js — MAIN world (Proton's own script; must reference no browser.*).
            if let root = PassBundle.rootURL,
               let wa = try? String(contentsOf: root.appendingPathComponent("webauthn.js"), encoding: .utf8) {
                addUserScript(wa, at: .atDocumentStart, world: .page, allFrames: true)
            }
            // Shields: fingerprint defense (farbling) — MAIN world, before page scripts.
            if ShieldsManager.shared.fingerprintProtection {
                addUserScript(FingerprintDefense.script, at: .atDocumentStart, world: .page, allFrames: true)
            }
        }

        // Broker handler registered ONLY for the isolated world — the page MAIN
        // world cannot reach webkit.messageHandlers.brokerIsolated.
        let bridge = IsolatedBridge(injector: self)
        config.userContentController.addScriptMessageHandler(
            bridge, contentWorld: isolatedWorld, name: "brokerIsolated")
        self.bridge = bridge

        // Media state channel (Mini Player), isolated world.
        config.userContentController.add(MediaHandler(injector: self), contentWorld: isolatedWorld, name: "muninnMedia")

        // Context-menu download capture (MAIN world): record the right-clicked image/link so the
        // menu can offer a *tracked* "Save Image to Library" / "Download Linked File" (WebKit's
        // native save bypasses WKDownloadDelegate, so we route our own download instead).
        let ctxScript = """
        document.addEventListener('contextmenu', function(e){ try {
          var t = e.target, img = '';
          if (t && t.tagName === 'IMG') img = t.currentSrc || t.src || '';
          if (!img && t && t.closest) { var im = t.closest('img'); if (im) img = im.currentSrc || im.src || ''; }
          var a = (t && t.closest) ? t.closest('a[href]') : null, link = a ? a.href : '';
          if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.muninnCtx)
            webkit.messageHandlers.muninnCtx.postMessage({ img: img || '', link: link || '' });
        } catch (_) {} }, true);
        """
        addUserScript(ctxScript, at: .atDocumentStart, world: .page, allFrames: true)
        config.userContentController.add(ContextMenuHandler(injector: self), contentWorld: .page, name: "muninnCtx")

        configHook?(config)
        let mwv = MuninnWebView(frame: .zero, configuration: config)
        mwv.onViewSource = { [weak self] wv in self?.onViewSource?(wv) }
        mwv.onDownload = { [weak self] url in self?.startDownload(url) }
        self.webView = mwv
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self
        // Inspectable in Developer Mode (user opt-in) or the human-supervised E6 gate.
        if #available(macOS 13.3, *) {
            self.webView.isInspectable = AppSettings.developerMode
                || ProcessInfo.processInfo.environment["MUNINN_E6_GATE"] != nil
        }
        // Register as the "page" push context so the broker can deliver events
        // (and future onMessage) into this isolated world.
        broker.registerContext(contextName, webView: webView, world: isolatedWorld)
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }

    /// Lifecycle symmetry with BackgroundHost (this owns a live networking WKWebView).
    func stop() {
        broker.unregisterContext(contextName)
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

extension InjectionCoordinator: WKNavigationDelegate {
    /// A committed main-frame navigation invalidates the subframe tree (FR-9). Reset
    /// on `didCommit` — the point WebKit guarantees the new document has replaced the
    /// old — NOT on provisional start, so a failed/cancelled navigation attempt can't
    /// blank out the subframes of a page that's still on screen. The main frame id
    /// stays 0; it re-registers on its next message.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        if let allow = onDecideJavaScript?(navigationAction.request.url) { preferences.allowsContentJavaScript = allow }
        decisionHandler(onNavigationAction?(navigationAction) ?? .allow, preferences)
    }

    // Downloads — non-displayable responses (attachments, binaries) become downloads.
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        broker.frameRegistry.resetSubframes()
    }

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

extension InjectionCoordinator {
    /// Reports play/pause of any `<video>`/`<audio>` on the page (capture-phase, so it catches
    /// elements added later) to the `muninnMedia` handler — drives the Mini Player.
    static let mediaProbeJS = """
    (function(){
      if (window.__muninnMedia) return; window.__muninnMedia = true;
      function anyPlaying(){
        try { return Array.prototype.some.call(document.querySelectorAll('video,audio'),
          function(m){ return !m.paused && !m.ended; }); } catch(e){ return false; }
      }
      function report(){ try { webkit.messageHandlers.muninnMedia.postMessage({playing: anyPlaying()}); } catch(e){} }
      ['play','playing','pause','ended','emptied'].forEach(function(ev){ document.addEventListener(ev, report, true); });
    })();
    """
}

@MainActor
private final class MediaHandler: NSObject, WKScriptMessageHandler {
    weak var injector: InjectionCoordinator?
    init(injector: InjectionCoordinator) { self.injector = injector }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        let playing = (message.body as? [String: Any])?["playing"] as? Bool ?? false
        injector?.onMediaState?(playing)
    }
}

/// Records the right-clicked image/link URL onto the MuninnWebView for the download menu items.
@MainActor
private final class ContextMenuHandler: NSObject, WKScriptMessageHandler {
    weak var injector: InjectionCoordinator?
    init(injector: InjectionCoordinator) { self.injector = injector }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body as? [String: Any]
        injector?.updateContextTargets(img: body?["img"] as? String, link: body?["link"] as? String)
    }
}

extension InjectionCoordinator {
    /// Update the web view's last right-clicked image/link (feeds the download menu items).
    func updateContextTargets(img: String?, link: String?) {
        guard let mwv = webView as? MuninnWebView else { return }
        mwv.lastCtxImageURL = (img?.isEmpty == false) ? URL(string: img!) : nil
        mwv.lastCtxLinkURL = (link?.isEmpty == false) ? URL(string: link!) : nil
    }

    /// Start a download that routes through our WKDownloadDelegate (so the Library records it).
    func startDownload(_ url: URL) {
        webView.startDownload(using: URLRequest(url: url)) { download in download.delegate = self }
    }
}

extension InjectionCoordinator: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        let folder = downloadFolder?() ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = suggestedFilename.isEmpty ? "download" : suggestedFilename
        var dest = folder.appendingPathComponent(name)
        // Avoid clobbering an existing file: "name.ext", "name-1.ext", …
        if FileManager.default.fileExists(atPath: dest.path) {
            let base = dest.deletingPathExtension().lastPathComponent
            let ext = dest.pathExtension
            var n = 1
            repeat {
                let candidate = ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)"
                dest = folder.appendingPathComponent(candidate); n += 1
            } while FileManager.default.fileExists(atPath: dest.path)
        }
        downloadInfo[ObjectIdentifier(download)] = (dest, response.url)
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        if let info = downloadInfo.removeValue(forKey: key) { onDownloadFinished?(info.dest, info.source) }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadInfo.removeValue(forKey: ObjectIdentifier(download))
    }
}

extension InjectionCoordinator: WKUIDelegate {
    /// `target="_blank"` / `window.open`: don't create a nested web view — hand the request
    /// to the host (new tab, or a Peek from a pinned tab).
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        NSLog("[peek] createWebView (blank) url=%@", navigationAction.request.url?.absoluteString ?? "?")
        onCreateWebView?(navigationAction)
        return nil
    }
}

/// Routes the isolated world's broker calls to the native MessageBroker.
@MainActor
private final class IsolatedBridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var injector: InjectionCoordinator?
    init(injector: InjectionCoordinator) { self.injector = injector }

    func userContentController(_ ucc: WKUserContentController,
                              didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let injector, let env = message.body as? [String: Any] else { return (nil, "bad envelope") }
        let ns = env["ns"] as? String
        let args = env["args"] as? [Any] ?? []
        // FR-9: register the calling frame on every message so getFrameId /
        // webNavigation.get*Frames can resolve it. Subframes parent to the main
        // frame (0) — precise nesting is post-MVP (Spike B risk #2, iframe autofill).
        let frameId = injector.broker.frameRegistry.resolve(message.frameInfo)
        // runtime.getFrameId self-resolution: the caller's own frame id.
        if ns == "runtime", (env["method"] as? String) == "__resolveFrameId" {
            return (frameId, nil)
        }
        // Control channels from content-polyfill.
        if ns == "__audit", let d = args.first as? [String: Any] {
            injector.broker.record(ns: (d["ns"] as? String) ?? "?", member: (d["member"] as? String) ?? "?",
                                   kind: (d["kind"] as? String) ?? "call", extra: ["stack": d["stack"] ?? ""])
            return (NSNull(), nil)
        }
        if ns == "__respond", let id = args.first as? String { // page-side sendResponse
            injector.broker.resolveResponse(id: id, result: args.count > 1 ? args[1] : nil)
            return (NSNull(), nil)
        }
        // Page-origin runtime.sendMessage → cross-context bus (delivered to the
        // host worker's onMessage; the return is background.js's sendResponse).
        if ns == "runtime", (env["method"] as? String) == "sendMessage" {
            let result = await injector.broker.routeSendMessageToHost(args.first, senderURL: injector.webView?.url?.absoluteString)
            return (result, nil)
        }
        // MAIN-world externally_connectable bridge (E6): a page's
        // chrome.runtime.sendMessage(extId, msg), relayed here from MAIN via the
        // isolated world. NATIVE ORIGIN GATE (defense-in-depth beyond the JS
        // location.host checks): only frames whose real securityOrigin host is a
        // manifest externally_connectable host reach onMessageExternal.
        if ns == "runtime", (env["method"] as? String) == "__externalMessage" {
            let host = message.frameInfo.securityOrigin.host.lowercased()
            guard PassBundle.externallyConnectableHosts.contains(host) else {
                return (nil, "origin not externally_connectable")
            }
            let result = await injector.broker.routeExternalMessageToHost(
                args.first, senderURL: message.frameInfo.request.url?.absoluteString)
            return (result, nil)
        }
        // Cross-context ports (page content script ⇄ background), same channel as the popup.
        if ns == "__port" {
            let m = env["method"] as? String
            let portId = args.first as? String ?? ""
            switch m {
            case "connect": injector.broker.portConnect(portId: portId, name: (args.count > 1 ? args[1] as? String : nil) ?? "",
                                                         from: injector.contextName, senderURL: injector.webView?.url?.absoluteString)
            case "message": injector.broker.portMessageFromClient(portId: portId, message: args.count > 1 ? args[1] : nil)
            case "disconnect": injector.broker.portDisconnect(portId: portId, origin: "client")
            default: break
            }
            return (NSNull(), nil)
        }
        // Everything else is a synchronous self-service Tier-1 call.
        do { return (try injector.broker.handle(env), nil) }
        catch { return (nil, String(describing: error)) }
    }
}
