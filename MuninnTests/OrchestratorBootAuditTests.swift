import XCTest
import WebKit
@testable import Muninn

/// E5 task 4 — orchestrator boot audit (headless, S1-style, content-side).
///
/// Purpose: give a repeatable harness for auditing what `browser.*` surface
/// orchestrator.js touches, and lock in that the full FR-9 injection set installs
/// and the isolated-world `__audit` plumbing works.
///
/// FINDING (2026-07-17, see `research/orchestrator-audit-2026-07-17.md`): the
/// full FR-9 set injects (5 user scripts) and the audit channel works, but
/// orchestrator's boot function does NOT complete in a *windowless* WKWebView —
/// its deferred boot depends on the render/idle-callback loop that an offscreen
/// web content process lacks (the same class of offscreen-throttling the E3
/// hardening fought, here on the page side). Routing `requestIdleCallback`→
/// `setTimeout` and keeping the process off RunningBoard suspension is not enough;
/// a fully headless boot would need an on-screen window (ground rule 2). The
/// **authoritative** boot evidence is therefore the live gate
/// (`research/e5-orchestrator-gate-2026-07-17.md`): orchestrator boots and runs
/// clean on the real visible page — 9 cross-context bus round-trips, onboarding
/// UI rendered, no crash — with the current modelled shim.
///
/// Decision 4b (ports): orchestrator initiates NO ports — `orchestrator.js` calls
/// no `runtime.connect`/`onConnect` (static scan); `background.js`'s 3 `onConnect`
/// handlers serve other contexts (dropdown/notification iframes), not orchestrator
/// boot. Cross-context ports stay DEFERRED off the E6 bus until a flow needs them.
@MainActor
final class OrchestratorBootAuditTests: XCTestCase {

    private func waitFor(_ desc: String, timeout: TimeInterval, _ cond: @escaping () -> Bool) async {
        let exp = expectation(description: desc); var done = false
        func poll() { if done { return }; if cond() { done = true; exp.fulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { poll() } }
        poll(); await fulfillment(of: [exp], timeout: timeout); done = true
    }

    /// Test-only instrumentation (isolated world, document_start, AFTER
    /// content-polyfill so `chrome`/`browser` exist): confirms the audit channel,
    /// routes idle callbacks to timers, and reports unhandled errors / port usage
    /// through the same `__audit` channel the polyfill uses.
    private static let instrumentation = """
    (function () {
      var g = globalThis;
      function rec(ns, member, kind) {
        try { g.webkit.messageHandlers.brokerIsolated.postMessage(
          { ns: "__audit", method: "record", args: [{ ns: ns, member: member, kind: kind }] }); } catch (e) {}
      }
      rec("__harness", "instrumentation", "loaded");
      // Windowless WKWebViews have no render loop, so requestIdleCallback never
      // fires; route it to a timer (which DOES fire under inactiveSchedulingPolicy=.none).
      g.requestIdleCallback = function (cb) {
        return g.setTimeout(function () { cb({ didTimeout: false, timeRemaining: function () { return 50; } }); }, 0);
      };
      g.cancelIdleCallback = function (id) { return g.clearTimeout(id); };
      g.addEventListener("error", function (e) { rec("window", "onerror", "error:" + ((e && e.message) || "")); });
      g.addEventListener("unhandledrejection", function (e) {
        var m = (e && e.reason && e.reason.message) || (e && String(e.reason)) || "";
        rec("window", "unhandledrejection", "error:" + m);
      });
      var r = g.chrome && g.chrome.runtime;
      if (r) {
        // Positive EXECUTION probes: modelled calls don't self-audit, so wrap the
        // ones orchestrator would hit on boot to distinguish "clean boot" from
        // "never executed".
        var os = r.sendMessage; r.sendMessage = function () { rec("runtime", "sendMessage", "exec-probe"); return os.apply(r, arguments); };
        var ou = r.getURL;      r.getURL = function () { rec("runtime", "getURL", "exec-probe"); return ou.apply(r, arguments); };
        if (typeof r.connect === "function") { var oc = r.connect;
          r.connect = function () { rec("runtime", "connect", "port-use"); return oc.apply(r, arguments); }; }
        if (r.onConnect && r.onConnect.addListener) { var oa = r.onConnect.addListener.bind(r.onConnect);
          r.onConnect.addListener = function (f) { rec("runtime", "onConnect", "port-listen"); return oa(f); }; }
      }
      var st = g.chrome && g.chrome.storage;
      if (st && st.local && st.local.get) { var og = st.local.get;
        st.local.get = function () { rec("storage", "local.get", "exec-probe"); return og.apply(st.local, arguments); }; }
    })();
    """

    func testOrchestratorInjectionAndAuditPlumbing() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        let host = BackgroundHost(broker: broker)
        let world = WKContentWorld.world(name: InjectionCoordinator.isolatedWorldName)
        // Instrumentation + keep-awake go in via the config hook (webView.configuration
        // is a copy, so post-creation addUserScript is futile).
        let injector = InjectionCoordinator(broker: broker) { config in
            config.userContentController.addUserScript(
                WKUserScript(source: Self.instrumentation, injectionTime: .atDocumentStart,
                             forMainFrameOnly: false, in: world))
            if #available(macOS 14.0, *) { config.preferences.inactiveSchedulingPolicy = .none }
        }
        defer { injector.stop(); host.stop() }

        host.start()
        await waitFor("host boot", timeout: 25) { host.bootSucceeded }

        injector.webView.loadHTMLString(
            "<!doctype html><html><body><form>"
            + "<input type=\"text\" name=\"username\" autocomplete=\"username\">"
            + "<input type=\"password\" name=\"password\" autocomplete=\"current-password\">"
            + "<button type=\"submit\">Sign in</button></form></body></html>",
            baseURL: URL(string: "https://example.com/login"))
        await waitFor("page load", timeout: 10) {
            injector.events.contains { ($0["kind"] as? String) == "didFinish" } }

        // Let orchestrator's boot path (idle→timer shimmed) run and settle.
        for _ in 0..<15 {
            _ = try? await injector.webView.callAsyncJavaScript(
                "return document.readyState", arguments: [:], in: nil, contentWorld: world)
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        // Flush any in-flight audit posts before snapshotting the surface.
        _ = await injector.probeIsolatedWorld()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Deduped audit surface → the artifact.
        var seen = Set<String>(); var surface: [String] = []
        for e in broker.auditLog {
            let key = "\(e["ns"] as? String ?? "?").\(e["member"] as? String ?? "?")\t[\(e["kind"] as? String ?? "?")]"
            if seen.insert(key).inserted { surface.append(key) }
        }
        print("=== ORCHESTRATOR-AUDIT-BEGIN ===")
        print(surface.sorted().joined(separator: "\n"))
        print("=== ORCHESTRATOR-AUDIT-END ===")

        // Invariants this harness genuinely locks in:
        // 1) the audit plumbing works (instrumentation landed a record).
        XCTAssertTrue(broker.auditLog.contains { ($0["ns"] as? String) == "__harness" },
                      "isolated-world __audit plumbing did not deliver the instrumentation record")
        // 2) the full FR-9 injection set installed and ordered correctly — the
        //    isolated world exposes the shim (bootstrap→content-polyfill ran).
        let hasShim = await injector.probeIsolatedWorld()
        XCTAssertTrue(hasShim, "isolated world should expose the shim (injection/order broken)")
        // 3) MAIN world stays clean under the full set (S2 holds).
        let main = await injector.probeMainWorld()
        XCTAssertEqual(main.chrome, "undefined", "chrome leaked into MAIN world")
        // 4) no unhandled-error storm reached the isolated error handler.
        let errors = broker.auditLog.compactMap { $0["kind"] as? String }.filter { $0.hasPrefix("error:") }
        for (i, e) in errors.prefix(20).enumerated() { print("ORCHESTRATOR-ERROR[\(i)]: \(e)") }
        XCTAssertLessThan(errors.count, 25, "unhandled-error storm during orchestrator injection")
        // 5) Decision 4b — orchestrator initiates no ports (no port-use/port-listen).
        XCTAssertFalse(broker.auditLog.contains {
            ($0["kind"] as? String) == "port-use" || ($0["kind"] as? String) == "port-listen" },
            "orchestrator initiated a port — revisit Decision 4b (cross-context ports)")
    }
}
