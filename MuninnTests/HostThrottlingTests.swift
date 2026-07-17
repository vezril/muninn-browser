import XCTest
import WebKit
@testable import Muninn

/// host-timer-fidelity: the no-window and process-isolation guarantees.
/// (Timer-fidelity itself is measured by the 4-arm bisect in the headless
/// diagnostic — see research/nfr10-residency-*-post-mitigation.md — because it
/// needs the adversarial idle conditions a unit test host can't create.)
@MainActor
final class HostThrottlingTests: XCTestCase {

    private var broker: MessageBroker!
    private var host: BackgroundHost!

    override func setUp() {
        broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        host = BackgroundHost(broker: broker)
    }
    override func tearDown() { host?.stop(); host = nil; broker = nil }

    private func waitFor(_ desc: String, timeout: TimeInterval, _ cond: @escaping () -> Bool) async {
        let exp = expectation(description: desc); var done = false
        func poll() { if done { return }; if cond() { done = true; exp.fulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { poll() } }
        poll(); await fulfillment(of: [exp], timeout: timeout); done = true
    }

    /// The mitigation must NOT introduce a user-visible window (ground rule 2).
    func testHostHasNoWindow() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let h = host!
        h.start()
        await waitFor("boot", timeout: 25) { h.bootSucceeded }
        XCTAssertNil(h.webView?.window, "background host WebView must not be in any window")
    }

    /// The throttling latch is per-process and one-way, so the host must run in
    /// its own WebContent process (dedicated data store). Assert its pid differs
    /// from an independent WebView's.
    func testHostRunsInDedicatedProcess() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let h = host!
        h.start()
        await waitFor("boot", timeout: 25) { h.bootSucceeded }

        let other = WKWebView(frame: .zero)
        other.loadHTMLString("<html><body>x</body></html>", baseURL: nil)
        await waitFor("other loaded", timeout: 10) {
            (other.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value ?? 0 > 0
        }
        let otherPID = (other.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value ?? -1
        guard let hostPID = h.webContentPID else { return XCTFail("no host pid") }
        XCTAssertNotEqual(hostPID, otherPID, "host must not share a WebContent process")
    }
}
