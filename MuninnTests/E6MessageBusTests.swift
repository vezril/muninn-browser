import XCTest
import WebKit
@testable import Muninn

/// E6 cross-context message bus: a page-origin `runtime.sendMessage` is delivered
/// to the host Worker's `onMessage` listener and the listener's `sendResponse`
/// is correlated back to the page — the exact path the auth-fork login rides.
/// Verified headlessly with synthetic contexts (no real login).
@MainActor
final class E6MessageBusTests: XCTestCase {

    private func waitFor(_ desc: String, timeout: TimeInterval, _ cond: @escaping () -> Bool) async {
        let exp = expectation(description: desc); var done = false
        func poll() { if done { return }; if cond() { done = true; exp.fulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { poll() } }
        poll(); await fulfillment(of: [exp], timeout: timeout); done = true
    }

    func testPageToHostSendMessageRoundTrip() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        let host = BackgroundHost(broker: broker)
        let page = ForkBridgeInjector(broker: broker, injectContentScripts: false) // pure bus, no orchestrator
        defer { page.stop(); host.stop() }

        host.firesLifecycleOnBoot = false // isolate to the pure bus; no onboarding listeners
        host.start()
        await waitFor("host boot", timeout: 25) { host.bootSucceeded }

        // A synthetic host-side onMessage listener (uniquely shaped so background.js
        // ignores it). It echoes the payload and the sender identity.
        host.evalInWorker(
            "browser.runtime.onMessage.addListener(function(m,s,sendResponse){"
            + "if(m&&m.__e6){sendResponse({echo:m.__e6, sender:(s&&s.id)});}});")

        // Load a page whose isolated world has the content shim.
        page.webView.loadHTMLString("<!doctype html><html><body>t</body></html>",
                                    baseURL: URL(string: "https://example.com/"))
        await waitFor("page load", timeout: 10) { page.events.contains { ($0["kind"] as? String) == "didFinish" } }

        // Page sends across contexts; the reply is background-side sendResponse.
        let r = try await page.webView.callAsyncJavaScript(
            "return await globalThis.browser.runtime.sendMessage({__e6:'ping'})",
            arguments: [:], in: nil,
            contentWorld: WKContentWorld.world(name: ForkBridgeInjector.isolatedWorldName))

        let dict = r as? [String: Any]
        XCTAssertEqual(dict?["echo"] as? String, "ping", "cross-context sendMessage did not deliver/return")
        XCTAssertEqual(dict?["sender"] as? String, PassBundle.canonicalID,
                       "sender identity should be the canonical extension id (ADR-008)")
    }
}
