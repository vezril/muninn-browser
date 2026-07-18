import XCTest
import WebKit
@testable import Muninn

/// S2 isolation tests (InjectionCoordinator): the load-bearing claim is that the
/// shim lives ONLY in an isolated content world — the page MAIN world stays
/// clean, so account.proton.me takes the postMessage fallback and hostile pages
/// can't reach the shim.
@MainActor
final class InjectionCoordinatorIsolationTests: XCTestCase {

    private var broker: MessageBroker!
    private var injector: InjectionCoordinator!

    override func setUp() {
        broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        injector = InjectionCoordinator(broker: broker)
    }
    override func tearDown() { injector?.stop(); injector = nil; broker = nil }

    private func waitFor(_ desc: String, timeout: TimeInterval, _ cond: @escaping () -> Bool) async {
        let exp = expectation(description: desc)
        var done = false
        func poll() { if done { return }; if cond() { done = true; exp.fulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll() } }
        poll(); await fulfillment(of: [exp], timeout: timeout); done = true
    }

    /// Fork-host scoping is a pure decision — no network.
    func testForkHostMatching() {
        XCTAssertTrue(InjectionCoordinator.matchesForkHost("account.proton.me"))
        XCTAssertTrue(InjectionCoordinator.matchesForkHost("ACCOUNT.PROTON.ME")) // case-folded
        // Exact host match (Chrome match-pattern semantics) — subdomains are NOT in scope.
        XCTAssertFalse(InjectionCoordinator.matchesForkHost("sub.account.proton.me"))
        XCTAssertFalse(InjectionCoordinator.matchesForkHost("example.com"))
        XCTAssertFalse(InjectionCoordinator.matchesForkHost("account.proton.me.evil.com"))
        XCTAssertFalse(InjectionCoordinator.matchesForkHost("proton.me"))
    }

    /// The core S2 guarantee, hermetic (loadHTMLString, no network): MAIN world
    /// has no browser API; the isolated world does.
    func testMainWorldIsIsolatedFromShim() async throws {
        let i = injector!
        i.webView.loadHTMLString("<!doctype html><html><body>t</body></html>",
                                 baseURL: URL(string: "https://example.com/"))
        await waitFor("load", timeout: 10) { i.events.contains { ($0["kind"] as? String) == "didFinish" } }

        let main = await i.probeMainWorld()
        XCTAssertEqual(main.chrome, "undefined", "window.chrome leaked into MAIN world (probeErr: \(i.lastProbeError))")
        XCTAssertEqual(main.browser, "undefined", "window.browser leaked into MAIN world")

        let isolatedHasShim = await i.probeIsolatedWorld()
        XCTAssertTrue(isolatedHasShim, "isolated world should expose the shim (probeErr: \(i.lastProbeError))")
    }

    /// The isolated-world broker handler is not reachable from the MAIN world.
    func testBrokerHandlerNotReachableFromMainWorld() async throws {
        let i = injector!
        i.webView.loadHTMLString("<!doctype html><html><body>t</body></html>",
                                 baseURL: URL(string: "https://example.com/"))
        await waitFor("load", timeout: 10) { i.events.contains { ($0["kind"] as? String) == "didFinish" } }

        let r = try? await i.webView.callAsyncJavaScript(
            "return typeof (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.brokerIsolated)",
            arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(r as? String, "undefined", "brokerIsolated handler reachable from MAIN world")
    }

    /// Relay plumbing: an isolated-world browser.runtime.sendMessage reaches the
    /// native broker and resolves (payload opaque). Hermetic.
    func testIsolatedRelayReachesBroker() async throws {
        let i = injector!
        i.webView.loadHTMLString("<!doctype html><html><body>t</body></html>",
                                 baseURL: URL(string: "https://example.com/"))
        await waitFor("load", timeout: 10) { i.events.contains { ($0["kind"] as? String) == "didFinish" } }

        // storage round-trip proves the isolated world → broker → back path.
        let js = """
        await window.webkit.messageHandlers.brokerIsolated.postMessage({ns:'storage',method:'local.set',args:[{s2:'ok'}]});
        const g = await window.webkit.messageHandlers.brokerIsolated.postMessage({ns:'storage',method:'local.get',args:['s2']});
        return g && g.s2;
        """
        let r = try? await i.webView.callAsyncJavaScript(
            js, arguments: [:], in: nil, contentWorld: WKContentWorld.world(name: InjectionCoordinator.isolatedWorldName))
        XCTAssertEqual(r as? String, "ok")
    }
}
