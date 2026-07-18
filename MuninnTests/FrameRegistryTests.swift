import XCTest
import WebKit
@testable import Muninn

/// FR-9 frame registry (E5 task 5): main frame id 0, stable subframe ids, and
/// `runtime.getFrameId` / `webNavigation.get*Frames` answered from it.
@MainActor
final class FrameRegistryTests: XCTestCase {

    private func waitFor(_ desc: String, timeout: TimeInterval, _ cond: @escaping () -> Bool) async {
        let exp = expectation(description: desc); var done = false
        func poll() { if done { return }; if cond() { done = true; exp.fulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll() } }
        poll(); await fulfillment(of: [exp], timeout: timeout); done = true
    }

    // MARK: - pure core

    /// getAllFrames on a (synthetic) nested-iframe tree: main id 0 + distinct
    /// subframe ids, each with its URL.
    func testGetAllFramesNested() {
        let reg = FrameRegistry()
        let main = reg.resolve(isMain: true, url: "https://a.example/", originKey: "https://a.example:0", parentId: -1)
        let f1 = reg.resolve(isMain: false, url: "https://a.example/child1", originKey: "https://a.example:0", parentId: 0)
        let f2 = reg.resolve(isMain: false, url: "https://a.example/child2", originKey: "https://a.example:0", parentId: 1)
        XCTAssertEqual(main, 0)
        XCTAssertNotEqual(f1, f2)
        XCTAssertTrue(f1 > 0 && f2 > 0)

        let all = reg.all()
        XCTAssertEqual(all.count, 3)
        let ids = all.compactMap { $0["frameId"] as? Int }.sorted()
        XCTAssertEqual(ids, [0, f1, f2].sorted())
        // main frame present with no parent
        XCTAssertEqual((all.first { ($0["frameId"] as? Int) == 0 })?["parentFrameId"] as? Int, -1)
        // each subframe carries its url
        XCTAssertEqual((all.first { ($0["frameId"] as? Int) == f1 })?["url"] as? String, "https://a.example/child1")
        XCTAssertEqual((all.first { ($0["frameId"] as? Int) == f2 })?["url"] as? String, "https://a.example/child2")
    }

    /// getFrame by id → details; unknown id → nil.
    func testGetFrameByIdAndUnknown() {
        let reg = FrameRegistry()
        reg.resolve(isMain: true, url: "https://a.example/", originKey: "https://a.example:0", parentId: -1)
        let f1 = reg.resolve(isMain: false, url: "https://a.example/c", originKey: "https://a.example:0", parentId: 0)

        let d = reg.frame(f1)
        XCTAssertEqual(d?["frameId"] as? Int, f1)
        XCTAssertEqual(d?["url"] as? String, "https://a.example/c")
        XCTAssertEqual(d?["parentFrameId"] as? Int, 0)

        XCTAssertNil(reg.frame(9999), "unknown frame id must be nil (→ null)")
    }

    /// The same frame (same origin+url) keeps its id; a new one gets a fresh id.
    func testStableIdsAcrossReResolve() {
        let reg = FrameRegistry()
        reg.resolve(isMain: true, url: "https://a/", originKey: "https://a:0", parentId: -1)
        let a1 = reg.resolve(isMain: false, url: "https://a/x", originKey: "https://a:0", parentId: 0)
        let a2 = reg.resolve(isMain: false, url: "https://a/x", originKey: "https://a:0", parentId: 0)
        let b = reg.resolve(isMain: false, url: "https://a/y", originKey: "https://a:0", parentId: 0)
        XCTAssertEqual(a1, a2, "same origin+url resolves to the same id")
        XCTAssertNotEqual(a1, b)
    }

    /// KNOWN LIMITATION (codified): same-origin subframes sharing a URL (the
    /// `about:blank`/`about:srcdoc` case) collapse into one id — the price of
    /// per-message id stability with no stable WKFrameInfo identity. If this ever
    /// changes (e.g. a real frame id becomes available), this test should be revised.
    func testIdenticalUrlSubframesCollapse_knownLimitation() {
        let reg = FrameRegistry()
        reg.resolve(isMain: true, url: "https://a/", originKey: "https://a:0", parentId: -1)
        let b1 = reg.resolve(isMain: false, url: "about:blank", originKey: "https://a:0", parentId: 0)
        let b2 = reg.resolve(isMain: false, url: "about:blank", originKey: "https://a:0", parentId: 0)
        XCTAssertEqual(b1, b2, "two same-origin about:blank frames currently merge (documented limitation)")
        XCTAssertEqual(reg.all().count, 2, "main + one merged blank-frame record")
    }

    /// resetSubframes clears the tree but keeps the main frame id 0.
    func testResetKeepsMain() {
        let reg = FrameRegistry()
        reg.resolve(isMain: true, url: "https://a/", originKey: "https://a:0", parentId: -1)
        _ = reg.resolve(isMain: false, url: "https://a/x", originKey: "https://a:0", parentId: 0)
        reg.resetSubframes()
        XCTAssertNotNil(reg.frame(0), "main frame survives reset")
        // next subframe id restarts at 1
        let n = reg.resolve(isMain: false, url: "https://a/z", originKey: "https://a:0", parentId: 0)
        XCTAssertEqual(n, 1)
    }

    // MARK: - integration (through the isolated bridge / message path)

    /// runtime.getFrameId from the MAIN frame resolves to 0, end to end.
    func testGetFrameIdMainFrameViaBridge() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        let injector = ForkBridgeInjector(broker: broker, injectContentScripts: false)
        defer { injector.stop() }
        let world = WKContentWorld.world(name: ForkBridgeInjector.isolatedWorldName)

        injector.webView.loadHTMLString("<!doctype html><html><body>main</body></html>",
                                        baseURL: URL(string: "https://example.com/"))
        await waitFor("load", timeout: 10) { injector.events.contains { ($0["kind"] as? String) == "didFinish" } }

        // Let content-polyfill's __resolveFrameId round-trip complete.
        await waitFor("frame registered", timeout: 5) { broker.frameRegistry.frame(0) != nil }

        let r = try await injector.webView.callAsyncJavaScript(
            "return globalThis.browser.runtime.getFrameId()", arguments: [:], in: nil, contentWorld: world)
        XCTAssertEqual((r as? NSNumber)?.intValue ?? (r as? Int), 0, "main-frame getFrameId must be 0")

        // webNavigation.getAllFrames (native) includes the main frame.
        let frames = try await injector.webView.callAsyncJavaScript(
            "return await globalThis.browser.webNavigation.getAllFrames({tabId:1})",
            arguments: [:], in: nil, contentWorld: world)
        let arr = frames as? [[String: Any]] ?? []
        XCTAssertTrue(arr.contains { ($0["frameId"] as? Int) == 0 }, "getAllFrames must include main frame 0")
    }

    /// A subframe resolves to a distinct positive id; getAllFrames then reports both.
    func testSubframeGetsDistinctId() async throws {
        try XCTSkipUnless(PassBundle.isPresent, "Pass bundle not embedded")
        let broker = MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
        let injector = ForkBridgeInjector(broker: broker, injectContentScripts: false)
        defer { injector.stop() }

        // srcdoc iframe: a real subframe, same-origin (inherits example.com).
        injector.webView.loadHTMLString(
            "<!doctype html><html><body>main"
            + "<iframe srcdoc=\"<!doctype html><html><body>child</body></html>\"></iframe>"
            + "</body></html>",
            baseURL: URL(string: "https://example.com/"))
        await waitFor("load", timeout: 10) { injector.events.contains { ($0["kind"] as? String) == "didFinish" } }

        // The subframe's content-polyfill boots and registers via __resolveFrameId.
        await waitFor("subframe registered", timeout: 6) { broker.frameRegistry.all().count >= 2 }

        let all = broker.frameRegistry.all()
        let ids = all.compactMap { $0["frameId"] as? Int }
        XCTAssertTrue(ids.contains(0), "main frame present")
        XCTAssertTrue(ids.contains { $0 > 0 }, "a subframe got a distinct positive id")
    }
}
