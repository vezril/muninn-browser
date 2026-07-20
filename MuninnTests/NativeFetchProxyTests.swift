import XCTest
import WebKit
@testable import Muninn

/// native-fetch-proxy: the extension worker's fetch to `*.proton.me` is routed through
/// native URLSession (CORS-bypassed), deny-by-default, and unreachable from page worlds.
@MainActor
final class NativeFetchProxyTests: XCTestCase {
    private func waitFor(_ desc: String, timeout: TimeInterval, _ cond: @escaping () -> Bool) async {
        let exp = expectation(description: desc); var done = false
        func poll() { if done { return }; if cond() { done = true; exp.fulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { poll() } }
        poll(); await fulfillment(of: [exp], timeout: timeout); done = true
    }
    private func scenario(_ h: BackgroundHost, _ name: String) -> [String: Any]? {
        h.bootLog.first { ($0["kind"] as? String) == "scenario" && ($0["name"] as? String) == name }
    }

    /// The allowlist is a proper host-suffix match — never a substring test.
    func testAllowlistSuffixMatch() {
        func ok(_ s: String) -> Bool { NativeFetchProxy.isAllowed(URL(string: s)!) }
        XCTAssertTrue(ok("https://proton.me/api"))
        XCTAssertTrue(ok("https://pass.proton.me/api/x"))
        XCTAssertTrue(ok("https://account.proton.me/"))
        XCTAssertFalse(ok("http://pass.proton.me/"), "must be https")
        XCTAssertFalse(ok("https://evilproton.me/"), "substring, not suffix")
        XCTAssertFalse(ok("https://proton.me.evil.com/"), "suffix spoof")
        XCTAssertFalse(ok("https://example.com/"))
    }

    /// Page/content-world JS cannot reach the proxy — the `__fetch` route lives only on
    /// the host's `broker` handler, not the page's `brokerIsolated`.
    func testProxyNotReachableFromPage() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        let page = InjectionCoordinator(broker: broker, injectContentScripts: false)
        defer { page.stop() }
        page.webView.loadHTMLString("<!doctype html><html><body>t</body></html>",
                                    baseURL: URL(string: "https://example.com/"))
        await waitFor("load", timeout: 10) { page.events.contains { ($0["kind"] as? String) == "didFinish" } }

        // A page-world __fetch call must NOT proxy — it falls to broker.handle → unmodelled → rejects.
        let js = """
        try {
          const r = await window.webkit.messageHandlers.brokerIsolated.postMessage(
            {ns:'__fetch', method:'request', args:[{url:'https://pass.proton.me/'}]});
          return 'resolved:' + JSON.stringify(r);
        } catch (e) { return 'rejected'; }
        """
        let r = try await page.webView.callAsyncJavaScript(
            js, arguments: [:], in: nil, contentWorld: WKContentWorld.world(name: InjectionCoordinator.isolatedWorldName))
        XCTAssertEqual(r as? String, "rejected", "page must not reach the native fetch proxy")
    }

    /// LIVE (net-gated): the worker's overridden fetch to an allowlisted host now
    /// SUCCEEDS through the proxy — the counterpart to ForkCorsProbeTests (raw fetch
    /// fails with CORS). Unauthenticated static asset; ground rule 1 not engaged.
    func testWorkerProxiedFetchSucceeds() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MUNINN_NET_PROBE"] == "1",
                          "network probe — set MUNINN_NET_PROBE=1 in the scheme to run")
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        let host = BackgroundHost(broker: broker)
        defer { host.stop() }
        host.firesLifecycleOnBoot = false
        host.start()
        await waitFor("boot", timeout: 25) { host.bootSucceeded }

        host.evalInWorker(
            "fetch('https://pass.proton.me/assets/version.json')"
            + ".then(function(r){return r.text().then(function(t){self.__report('proxyfetch', r.ok && t.length>0, {status:r.status})})},"
            + "function(e){self.__report('proxyfetch', false, {err:String(e)})})")
        await waitFor("proxy fetch report", timeout: 15) { self.scenario(host, "proxyfetch") != nil }
        let s = scenario(host, "proxyfetch")
        print("PROXY-FETCH: \(String(describing: s))")
        XCTAssertEqual(s?["ok"] as? Bool, true, "worker fetch to *.proton.me must succeed through the native proxy")
    }
}
