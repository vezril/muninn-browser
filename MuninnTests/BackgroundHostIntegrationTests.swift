import XCTest
import WebKit
@testable import Muninn

/// Integration tests that boot Proton's real background.js in the background
/// host (real WKWebView + DedicatedWorker). Cover the background-host spec's
/// boot scenarios (S1) and an end-to-end worker→native round-trip.
@MainActor
final class BackgroundHostIntegrationTests: XCTestCase {

    private var broker: MessageBroker!
    private var host: BackgroundHost!

    override func setUp() {
        broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        host = BackgroundHost(broker: broker)
    }

    override func tearDown() {
        host?.stop()
        host = nil; broker = nil
    }

    /// Await until `cond` holds or the timeout elapses (main-actor poll).
    /// Stops polling once fulfilled/returned so no stray closure outlives tearDown.
    private func waitFor(_ desc: String, timeout: TimeInterval, _ cond: @escaping () -> Bool) async {
        let exp = expectation(description: desc)
        var done = false
        func poll() {
            if done { return }
            if cond() { done = true; exp.fulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { poll() }
        }
        poll()
        await fulfillment(of: [exp], timeout: timeout)
        done = true
    }

    /// Terminate a WKWebView's WebContent process for real (private PID + SIGKILL,
    /// falling back to the private selector). Deterministically fires
    /// `webViewWebContentProcessDidTerminate`.
    private func killWebContent(_ webView: WKWebView) {
        if let pid = (webView.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value, pid > 0 {
            kill(pid, SIGKILL)
        } else {
            webView.perform(Selector(("_killWebContentProcess")))
        }
    }

    func testBackgroundJsBootsClean() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        host.firesLifecycleOnBoot = false // measure pure module load, not the onboarding flow
        host.start()
        await waitFor("backgroundLoaded", timeout: 25) { self.host.bootSucceeded }
        // Settle for late errors/rejections.
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertFalse(host.hasErrors, "boot produced worker errors/rejections")
        // Only the known-benign chrome.app probe should be audited (if anything).
        let unexpected = broker.auditLog.filter {
            !(($0["ns"] as? String) == "<root>" && ($0["member"] as? String) == "app")
        }
        XCTAssertTrue(unexpected.isEmpty, "unexpected audited API accesses at boot: \(unexpected)")
    }

    /// True if a `__report(name, true)` fired from the worker.
    private func scenarioOK(_ h: BackgroundHost, _ name: String) -> Bool {
        h.bootLog.contains {
            ($0["kind"] as? String) == "scenario" && ($0["name"] as? String) == name && ($0["ok"] as? Bool) == true
        }
    }

    func testWorkerToNativeStorageRoundTrip() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let h = host!
        h.start()
        await waitFor("backgroundLoaded", timeout: 25) { h.bootSucceeded }

        h.evalInWorker(
            "browser.storage.local.set({rt:'ok'}).then(function(){return browser.storage.local.get('rt')})"
            + ".then(function(r){self.__report('rt', r.rt==='ok')})")

        await waitFor("round-trip report", timeout: 6) { self.scenarioOK(h, "rt") }
        XCTAssertTrue(scenarioOK(h, "rt"))
    }

    func testUnmodelledApiRejectsInWorkerWithoutThrowing() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let h = host!
        h.start()
        await waitFor("backgroundLoaded", timeout: 25) { h.bootSucceeded }

        // Access to an unmodelled member must reject (not throw at property access).
        // ok=true only if we reached the reject handler without a synchronous throw.
        h.evalInWorker(
            "try{browser.nope.doesNotExist().then(function(){self.__report('unmodelled',false)},"
            + "function(){self.__report('unmodelled',true)})}catch(e){self.__report('unmodelled',false)}")

        await waitFor("unmodelled report", timeout: 6) { self.scenarioOK(h, "unmodelled") }
        XCTAssertTrue(scenarioOK(h, "unmodelled"), "unmodelled access should reject, not throw")
        XCTAssertFalse(h.hasErrors)
    }

    /// Watchdog: killing the host's own WebContent process triggers a reload,
    /// a logged restart, and the host comes back with storage.local intact.
    func testWatchdogRestartsAfterWebContentCrash() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let h = host! // strong local ref so leftover polls survive tearDown
        h.start()
        await waitFor("backgroundLoaded", timeout: 25) { h.bootSucceeded }

        // Persist a value through the shim, then crash the WebContent process.
        _ = try broker.handle(["ns": "storage", "method": "local.set", "args": [["survives": "yes"]]])
        guard let wv = h.webView else { return XCTFail("no webView") }
        killWebContent(wv)

        await waitFor("restart logged", timeout: 20) {
            h.bootLog.contains { ($0["kind"] as? String) == "watchdogRestart" }
        }
        // After restart the host re-boots background.js; storage.local survives.
        await waitFor("re-boot", timeout: 25) {
            h.bootLog.filter { ($0["kind"] as? String) == "host:backgroundLoaded" }.count >= 2
        }
        XCTAssertEqual(
            (try broker.handle(["ns": "storage", "method": "local.get", "args": ["survives"]]) as? [String: Any])?["survives"] as? String,
            "yes")
    }

    /// Isolation: a sibling WKWebView crashing does not disturb the host.
    func testSiblingCrashDoesNotAffectHost() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let h = host!
        h.start()
        await waitFor("backgroundLoaded", timeout: 25) { h.bootSucceeded }
        let bootsBefore = h.bootLog.filter { ($0["kind"] as? String) == "host:backgroundLoaded" }.count

        // A separate WKWebView (distinct WebContent process) is really killed.
        let sibling = WKWebView(frame: .zero)
        sibling.loadHTMLString("<html><body>sibling</body></html>", baseURL: nil)
        try? await Task.sleep(nanoseconds: 800_000_000)
        killWebContent(sibling)
        try? await Task.sleep(nanoseconds: 2_500_000_000)

        // Host neither restarted nor errored.
        let bootsAfter = h.bootLog.filter { ($0["kind"] as? String) == "host:backgroundLoaded" }.count
        XCTAssertEqual(bootsBefore, bootsAfter, "host should not have re-booted")
        XCTAssertFalse(h.bootLog.contains { ($0["kind"] as? String) == "watchdogRestart" })
        XCTAssertFalse(h.hasErrors)
    }
}
