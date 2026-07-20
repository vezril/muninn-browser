import XCTest
import WebKit
@testable import Muninn

/// E7 cross-context ports: a client `runtime.connect(id,{name})` reaches the host
/// worker's `onConnect`, and messages flow BOTH ways over the port — the channel
/// popup.js drives its entire UI over. Exercised via the page context (same
/// `content-polyfill` port code the popup uses in its MAIN world).
@MainActor
final class CrossContextPortTests: XCTestCase {
    private func waitFor(_ desc: String, timeout: TimeInterval, _ cond: @escaping () -> Bool) async {
        let exp = expectation(description: desc); var done = false
        func poll() { if done { return }; if cond() { done = true; exp.fulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { poll() } }
        poll(); await fulfillment(of: [exp], timeout: timeout); done = true
    }

    func testPortRoundTripClientToHostAndBack() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        let host = BackgroundHost(broker: broker)
        let page = InjectionCoordinator(broker: broker, injectContentScripts: false)
        defer { page.stop(); host.stop() }
        host.firesLifecycleOnBoot = false
        host.start()
        await waitFor("host boot", timeout: 25) { host.bootSucceeded }

        // Host-side onConnect echo: for each incoming port, echo any message back.
        host.evalInWorker(
            "browser.runtime.onConnect.addListener(function(port){"
            + "port.onMessage.addListener(function(m){ port.postMessage({echo:m, portName:port.name}); });});")

        page.webView.loadHTMLString("<!doctype html><html><body>t</body></html>",
                                    baseURL: URL(string: "https://example.com/"))
        await waitFor("load", timeout: 10) { page.events.contains { ($0["kind"] as? String) == "didFinish" } }

        // Client connects, sends a message, and awaits the echo over the SAME port.
        let world = WKContentWorld.world(name: InjectionCoordinator.isolatedWorldName)
        let r = try await page.webView.callAsyncJavaScript("""
        return await new Promise(function (resolve) {
          var port = globalThis.browser.runtime.connect(globalThis.browser.runtime.id, {name: "popup"});
          port.onMessage.addListener(function (m) { resolve(JSON.stringify(m)); });
          port.postMessage({ hi: 1 });
          setTimeout(function () { resolve("timeout"); }, 6000);
        });
        """, arguments: [:], in: nil, contentWorld: world)

        let s = r as? String ?? ""
        let d = s.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertNotEqual(s, "timeout", "port round-trip did not complete")
        XCTAssertEqual((d?["echo"] as? [String: Any])?["hi"] as? Int, 1, "message did not round-trip over the port")
        XCTAssertEqual(d?["portName"] as? String, "popup", "port name should reach the host onConnect")
    }
}
