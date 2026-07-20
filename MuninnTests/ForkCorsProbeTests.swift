import XCTest
import WebKit
@testable import Muninn

/// Diagnostic (E6 session-fork blocker): the auth-fork consume is a cross-origin
/// fetch from the background worker (origin `muninn-ext://<id>`) to
/// `https://pass.proton.me/api` with `credentials:"include"`. In a real browser the
/// extension's host_permissions bypass CORS; a WKWebView custom-scheme origin gets
/// no such privilege. This probe confirms whether such a fetch is CORS-blocked —
/// unauthenticated, no credentials/selector, so ground rule 1 is not engaged.
///
/// Network-dependent: skipped unless MUNINN_NET_PROBE=1 so it never flakes CI.
@MainActor
final class ForkCorsProbeTests: XCTestCase {
    private func waitFor(_ desc: String, timeout: TimeInterval, _ cond: @escaping () -> Bool) async {
        let exp = expectation(description: desc); var done = false
        func poll() { if done { return }; if cond() { done = true; exp.fulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { poll() } }
        poll(); await fulfillment(of: [exp], timeout: timeout); done = true
    }
    private func scenario(_ h: BackgroundHost, _ name: String) -> [String: Any]? {
        h.bootLog.first { ($0["kind"] as? String) == "scenario" && ($0["name"] as? String) == name }
    }

    func testWorkerCrossOriginFetchToProtonApi() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MUNINN_NET_PROBE"] == "1",
                          "network probe — set MUNINN_NET_PROBE=1 in the scheme to run")
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        // CONFIRMED 2026-07-18: this fetch fails with "TypeError: Load failed"
        // (WebKit's CORS-blocked signature). The extension's cross-origin API fetch
        // needs a native fetch proxy — see research/e6-external-gate-2026-07-17.md.
        let broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        let host = BackgroundHost(broker: broker)
        defer { host.stop() }
        host.firesLifecycleOnBoot = false
        host.start()
        await waitFor("boot", timeout: 25) { host.bootSucceeded }

        // Benign, unauthenticated static asset (VERSION_PATH). credentials:"include"
        // mirrors the fork-consume fetch, but the store is empty so no cookie is sent.
        host.evalInWorker(
            "fetch('https://pass.proton.me/assets/version.json', {credentials:'include'})"
            + ".then(function(r){self.__report('cors', true, {status:r.status})},"
            + "function(e){self.__report('cors', false, {err:String(e)})})")

        await waitFor("cors report", timeout: 15) { self.scenario(host, "cors") != nil }
        let s = scenario(host, "cors")
        print("FORK-CORS-PROBE: \(String(describing: s))")
        // No assertion on the outcome — the printed result IS the diagnostic. A
        // failure (ok=false, TypeError/Load failed) confirms CORS blocks the
        // extension's API fetch → a native fetch proxy is required.
        XCTAssertNotNil(s, "probe should report")
    }
}
