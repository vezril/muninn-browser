import XCTest
import WebKit
@testable import Muninn

/// E6 externally_connectable bridge: the page MAIN world on a manifest
/// externally_connectable origin gets a narrow `chrome.runtime` that reaches
/// `background.js`'s `onMessageExternal` — the account app's extension-detection
/// path — while every other origin's MAIN world stays clean (S2/ADR-007).
@MainActor
final class E6ExternalConnectableTests: XCTestCase {

    private func waitFor(_ desc: String, timeout: TimeInterval, _ cond: @escaping () -> Bool) async {
        let exp = expectation(description: desc); var done = false
        func poll() { if done { return }; if cond() { done = true; exp.fulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { poll() } }
        poll(); await fulfillment(of: [exp], timeout: timeout); done = true
    }

    /// MAIN-world `chrome.runtime.sendMessage(extId, msg)` on account.proton.me →
    /// host worker `onMessageExternal` → `sendResponse` → back to the page.
    func testExternalMessageRoundTrip() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        let host = BackgroundHost(broker: broker)
        let page = InjectionCoordinator(broker: broker, injectContentScripts: false)
        defer { page.stop(); host.stop() }
        host.firesLifecycleOnBoot = false
        host.start()
        await waitFor("host boot", timeout: 25) { host.bootSucceeded }

        // Synthetic host-side onMessageExternal listener: echoes payload + sender origin.
        host.evalInWorker(
            "browser.runtime.onMessageExternal.addListener(function(m,s,sendResponse){"
            + "if(m&&m.__ext){sendResponse({echo:m.__ext, origin:(s&&s.origin)});}});")

        page.webView.loadHTMLString("<!doctype html><html><body>acct</body></html>",
                                    baseURL: URL(string: "https://account.proton.me/"))
        await waitFor("load", timeout: 10) { page.events.contains { ($0["kind"] as? String) == "didFinish" } }

        // Call from the page MAIN world (not the isolated world) — the real account app's context.
        let r = try await page.webView.callAsyncJavaScript(
            "return await window.chrome.runtime.sendMessage(\"\(PassBundle.canonicalID)\", {__ext:'ping'})",
            arguments: [:], in: nil, contentWorld: .page)
        let dict = r as? [String: Any]
        XCTAssertEqual(dict?["echo"] as? String, "ping", "MAIN-world external sendMessage did not round-trip")
        XCTAssertEqual(dict?["origin"] as? String, "https://account.proton.me",
                       "onMessageExternal sender.origin should be the page origin")
    }

    /// The narrow bridge is present on a blessed origin: only runtime.{id,sendMessage,connect}.
    func testBridgeShapeOnBlessedOrigin() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        let page = InjectionCoordinator(broker: broker, injectContentScripts: false)
        defer { page.stop() }
        page.webView.loadHTMLString("<!doctype html><html><body>acct</body></html>",
                                    baseURL: URL(string: "https://account.proton.me/"))
        await waitFor("load", timeout: 10) { page.events.contains { ($0["kind"] as? String) == "didFinish" } }

        let r = try await page.webView.callAsyncJavaScript(
            "return JSON.stringify({"
            + " sm: typeof (window.chrome&&window.chrome.runtime&&window.chrome.runtime.sendMessage),"
            + " id: (window.chrome&&window.chrome.runtime&&window.chrome.runtime.id) || null,"
            + " cn: typeof (window.chrome&&window.chrome.runtime&&window.chrome.runtime.connect) })",
            arguments: [:], in: nil, contentWorld: .page)
        let d = (r as? String)?.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertEqual(d?["sm"] as? String, "function", "MAIN chrome.runtime.sendMessage should exist on blessed origin")
        XCTAssertEqual(d?["id"] as? String, PassBundle.canonicalID, "MAIN chrome.runtime.id should be canonical")
        XCTAssertEqual(d?["cn"] as? String, "function", "MAIN chrome.runtime.connect should exist")
    }

    /// S2 preserved: a non-blessed origin's MAIN world stays completely clean.
    func testMainWorldCleanOnNonBlessedOrigin() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        let page = InjectionCoordinator(broker: broker, injectContentScripts: false)
        defer { page.stop() }
        page.webView.loadHTMLString("<!doctype html><html><body>x</body></html>",
                                    baseURL: URL(string: "https://example.com/"))
        await waitFor("load", timeout: 10) { page.events.contains { ($0["kind"] as? String) == "didFinish" } }

        let main = await page.probeMainWorld()
        XCTAssertEqual(main.chrome, "undefined", "MAIN chrome must stay undefined on a non-blessed origin (S2)")
        XCTAssertEqual(main.browser, "undefined", "MAIN browser must stay undefined on a non-blessed origin (S2)")
    }
}
