import XCTest
import WebKit
@testable import Muninn

/// E7-minimal-popup: the popup renders Proton's popup.html with the shim in its MAIN
/// world (trusted extension page), broker-wired, so "Sign in" can initiate the auth-fork.
@MainActor
final class PopupHostTests: XCTestCase {
    private func waitFor(_ desc: String, timeout: TimeInterval, _ cond: @escaping () -> Bool) async {
        let exp = expectation(description: desc); var done = false
        func poll() { if done { return }; if cond() { done = true; exp.fulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { poll() } }
        poll(); await fulfillment(of: [exp], timeout: timeout); done = true
    }

    func testPopupLoadsWithShimInMainWorld() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        let popup = PopupHost(broker: broker)
        defer { popup.stop() }
        popup.load()
        await waitFor("popup load", timeout: 15) {
            popup.events.contains { ($0["kind"] as? String) == "didFinish" || ($0["kind"] as? String) == "didFail" } }

        // popup.html itself served + loaded (not a scheme-handler 404 / didFail).
        XCTAssertTrue(popup.events.contains { ($0["kind"] as? String) == "didFinish" },
                      "popup.html should load via the scheme handler (events: \(popup.events))")

        // The shim is present in the popup's MAIN world (trusted extension page).
        let r = try await popup.webView.callAsyncJavaScript(
            "return JSON.stringify({ chrome: typeof window.chrome, runtime: typeof (window.chrome&&window.chrome.runtime),"
            + " storage: typeof (window.chrome&&window.chrome.storage), id: (window.chrome&&window.chrome.runtime&&window.chrome.runtime.id)||null })",
            arguments: [:], in: nil, contentWorld: .page)
        let d = (r as? String)?.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertEqual(d?["chrome"] as? String, "object", "chrome should be in the popup MAIN world")
        XCTAssertEqual(d?["runtime"] as? String, "object")
        XCTAssertEqual(d?["storage"] as? String, "object")
        XCTAssertEqual(d?["id"] as? String, PassBundle.canonicalID)
    }
}
