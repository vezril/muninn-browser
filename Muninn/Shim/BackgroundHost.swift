import Foundation
import WebKit

/// The always-resident background service-worker host (FR-7, ADR-005 as refined
/// 2026-07-12): a hidden, non-rendering WKWebView that loads a minimal host page
/// which runs Proton's `background.js` in a DedicatedWorker. Owns the scheme
/// handler, the native message-handler bridge to the MessageBroker, the process
/// activity assertion, and the crash watchdog.
@MainActor
final class BackgroundHost: NSObject {
    let broker: MessageBroker
    private(set) var webView: WKWebView?
    private var activity: NSObjectProtocol?
    private var restarts: [Date] = []
    private var stopped = false

    /// Whether the extension install lifecycle event has been fired this run.
    var hasFiredInstalled = false

    /// Fire runtime.onInstalled/onStartup on boot (drives the onboarding/fork
    /// flow). The pure S1 boot-clean test sets this false to measure module load
    /// in isolation; the app leaves it true.
    var firesLifecycleOnBoot = true

    /// Lifecycle/boot observations for the S1 audit (console lines, worker
    /// errors, host events). Each is a [String: Any] with a "kind".
    private(set) var bootLog: [[String: Any]] = []
    var onBootEvent: (([String: Any]) -> Void)?

    init(broker: MessageBroker) {
        self.broker = broker
        super.init()
    }

    func start() {
        guard webView == nil else { return }
        stopped = false

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(ExtensionSchemeHandler(), forURLScheme: PassBundle.scheme)
        HostThrottling.apply(to: config, host: self)

        let bridge = HostBridge(host: self)
        config.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "broker")
        config.userContentController.add(bridge, name: "audit")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        // Gate-mode only: Safari Web Inspector on the background host page (so its
        // Worker's console — e.g. background.js "[Activation] missing permissions" —
        // is visible during a supervised diagnostic gate). Never in a shipping run.
        if ProcessInfo.processInfo.environment["MUNINN_E6_GATE"] != nil, #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        self.webView = webView
        broker.registerContext("host", webView: webView, world: nil)

        // Keep the host resident: hold ONE process activity assertion for the
        // host's lifetime (ADR-005; process-granular, minimum-necessary under
        // NFR-10). Guard against re-acquiring on watchdog restart — start() is
        // called again by restart(), and a second beginActivity would leak the
        // first assertion (found in review).
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Muninn background host resident")
        }

        webView.load(URLRequest(url: PassBundle.originURL.appendingPathComponent("background-host.html")))
        note(kind: "hostStarting", info: ["version": PassBundle.version])
    }

    func stop() {
        stopped = true
        webView?.stopLoading()
        webView = nil
        broker.unregisterContext("host")
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
    }

    // MARK: - watchdog

    private func restart(reason: String) {
        guard !stopped else { return }
        let now = Date()
        restarts = restarts.filter { now.timeIntervalSince($0) < 600 }
        restarts.append(now)
        note(kind: "watchdogRestart", info: ["reason": reason, "recentRestarts": restarts.count])
        if restarts.count > 3 {
            note(kind: "watchdogStopped", info: ["reason": "restart storm (>3 in 10 min)"])
            stop()
            return
        }
        webView = nil
        start()
    }

    // MARK: - audit plumbing

    func note(kind: String, info: [String: Any] = [:]) {
        var entry: [String: Any] = ["kind": kind, "at": Date().timeIntervalSince1970]
        entry.merge(info) { a, _ in a }
        bootLog.append(entry)
        onBootEvent?(entry)
    }

    /// Run a snippet inside the background Worker (diagnostic/scenario use).
    func evalInWorker(_ code: String) {
        guard let webView else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: [code]),
              let arr = String(data: data, encoding: .utf8) else { return }
        // arr is ["...escaped..."]; unwrap to the single JS string literal.
        let literal = String(arr.dropFirst().dropLast())
        webView.evaluateJavaScript("window.__shimEval(\(literal))")
    }

    /// The host's WebContent process id (SPI, test-only — asserts process isolation
    /// from tabs, required for the per-process throttling latch to hold).
    var webContentPID: pid_t? {
        guard let wv = webView, let n = wv.value(forKey: "_webProcessIdentifier") as? NSNumber else { return nil }
        return n.int32Value > 0 ? n.int32Value : nil
    }

    /// Snapshot for the audit artifact writer.
    var bootSucceeded: Bool { bootLog.contains { ($0["kind"] as? String) == "host:backgroundLoaded" } }
    var hasErrors: Bool {
        bootLog.contains { ["workerError", "workerRejection"].contains($0["kind"] as? String ?? "") }
    }
}

// MARK: - navigation / crash watchdog

extension BackgroundHost: WKNavigationDelegate {
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        note(kind: "webContentTerminated")
        restart(reason: "WebContent process terminated")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        note(kind: "navigationFailed", info: ["error": error.localizedDescription])
    }
}

// MARK: - native bridge (page ⇄ broker)

/// Receives the host page's "broker" (with reply) and "audit" messages.
/// WebKit's handler protocols are main-actor-isolated in the current SDK, so a
/// @MainActor class conforms directly.
@MainActor
private final class HostBridge: NSObject, WKScriptMessageHandlerWithReply, WKScriptMessageHandler {
    weak var host: BackgroundHost?
    init(host: BackgroundHost) { self.host = host }

    func userContentController(_ ucc: WKUserContentController,
                              didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let host, let env = message.body as? [String: Any] else {
            return (nil, "bad envelope")
        }
        // Fork-gate diagnostic: worker error text (class + short message). Logged only when gated.
        if (env["ns"] as? String) == "__forkdiag" {
            if ProcessInfo.processInfo.environment["MUNINN_FORKGATE"] != nil {
                let txt = ((env["args"] as? [Any])?.first as? String) ?? "?"
                let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("Muninn/fork-gate.log")
                let line = "\(Date().ISO8601Format()) worker error: \(txt)\n"
                if let fh = try? FileHandle(forWritingTo: u) { fh.seekToEndOfFile(); fh.write(Data(line.utf8)); try? fh.close() }
                else { try? line.data(using: .utf8)?.write(to: u) }
            }
            return (NSNull(), nil)
        }
        // Native fetch proxy (host-only route — the page's IsolatedBridge has no such
        // branch, so content worlds can't reach it). Async: awaits URLSession.
        if (env["ns"] as? String) == "__fetch", (env["method"] as? String) == "request" {
            return (await host.broker.performFetch(env), nil)
        }
        // Safe entry probe: the worker called fetch (host only, before routing).
        if (env["ns"] as? String) == "__fetch", (env["method"] as? String) == "probe" {
            let h = ((env["args"] as? [Any])?.first as? String) ?? "?"
            host.broker.onFetchProbe?("ENTRY", h, 0, false)
            if ProcessInfo.processInfo.environment["MUNINN_FORKGATE"] != nil {
                let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("Muninn/fork-gate.log")
                let line = "\(Date().ISO8601Format()) worker fetch probe host=\(h)\n"
                if let fh = try? FileHandle(forWritingTo: u) { fh.seekToEndOfFile(); fh.write(Data(line.utf8)); try? fh.close() }
                else { try? line.data(using: .utf8)?.write(to: u) }
            }
            return (NSNull(), nil)
        }
        do { return (try host.broker.handle(env), nil) }
        catch { return (nil, String(describing: error)) }
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let host, let d = message.body as? [String: Any] else { return }
        let kind = (d["__shim"] as? String) ?? "audit"
        switch kind {
        case "console":
            // Only warn/error carry text (credential safety); others length-only.
            var cinfo: [String: Any] = ["level": d["level"] ?? "log"]
            if let t = d["text"] { cinfo["text"] = t } else if let l = d["len"] { cinfo["len"] = l }
            host.note(kind: "console", info: cinfo)
        case "scenario":
            var sinfo: [String: Any] = ["name": d["name"] ?? "?", "ok": d["ok"] ?? false]
            if let v = d["value"] { sinfo["value"] = v }
            host.note(kind: "scenario", info: sinfo)
        case "response":
            // A worker onMessage listener's sendResponse — resolve the parked
            // cross-context continuation (E6 message bus).
            if let id = d["id"] as? String { host.broker.resolveResponse(id: id, result: d["result"]) }
        case "workerError", "workerRejection":
            host.note(kind: kind, info: d)
        case "portPost":
            // A worker-side port.postMessage → route to the client port (popup/page).
            if let portId = d["portId"] as? String { host.broker.portMessageFromHost(portId: portId, message: d["message"]) }
        case "portDisconnectHost":
            if let portId = d["portId"] as? String { host.broker.portDisconnect(portId: portId, origin: "host") }
        case "audit":
            if let ns = d["ns"] as? String, let member = d["member"] as? String {
                host.broker.record(ns: ns, member: member,
                                   kind: (d["kind"] as? String) ?? "call",
                                   extra: ["stack": d["stack"] ?? ""])
            }
        case "hostEvent":
            let event = (d["event"] as? String) ?? "?"
            host.note(kind: "host:" + event, info: d)
            if event == "backgroundLoaded" && host.firesLifecycleOnBoot {
                // Fire the extension lifecycle event so background.js runs its
                // install/onboarding hook (which drives the auth-fork URL). A real
                // browser fires runtime.onInstalled once on install / onStartup after.
                host.broker.fireExtensionLifecycle(firstRun: !host.hasFiredInstalled)
                host.hasFiredInstalled = true
            }
        default:
            host.note(kind: "audit", info: d)
        }
    }
}
