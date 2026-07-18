import XCTest
import WebKit
@testable import Muninn

/// Diagnostic: reproduce background.js's activation permission check
/// `permissions.contains({origins: host_permissions})` in the real worker and see
/// what the shim returns — this gates the "missing permissions" state.
@MainActor
final class PermissionsProbeTests: XCTestCase {
    private func waitFor(_ desc: String, timeout: TimeInterval, _ cond: @escaping () -> Bool) async {
        let exp = expectation(description: desc); var done = false
        func poll() { if done { return }; if cond() { done = true; exp.fulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { poll() } }
        poll(); await fulfillment(of: [exp], timeout: timeout); done = true
    }
    private func scenario(_ h: BackgroundHost, _ name: String) -> [String: Any]? {
        h.bootLog.first { ($0["kind"] as? String) == "scenario" && ($0["name"] as? String) == name }
    }

    func testPermissionsContainsInWorker() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        let host = BackgroundHost(broker: broker)
        defer { host.stop() }
        host.firesLifecycleOnBoot = false
        host.start()
        await waitFor("boot", timeout: 25) { host.bootSucceeded }

        // Exactly background.js's l0: permissions.contains({origins: host_permissions})
        host.evalInWorker(
            "Promise.resolve(browser.permissions.contains({origins:['*://*/*']}))"
            + ".then(function(r){self.__report('perm', r===true, {typeof:typeof r, val:JSON.stringify(r)})},"
            + "function(e){self.__report('perm', false, {err:String(e)})})")

        await waitFor("perm report", timeout: 6) { self.scenario(host, "perm") != nil }
        let s = scenario(host, "perm")
        print("PERM-PROBE: \(String(describing: s))")
        XCTAssertEqual(s?["ok"] as? Bool, true, "permissions.contains must return true so background.js sees granted")
    }
}
