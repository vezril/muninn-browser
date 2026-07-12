import XCTest
@testable import Muninn

/// Native, fast Tier-1 + broker tests (no WKWebView). Cover the message-broker
/// and tier1-api-stubs specs' non-integration scenarios.
@MainActor
final class ShimUnitTests: XCTestCase {

    // MARK: - storage

    func testStorageGetSetRemoveClear() {
        let s = ExtensionStorage(inMemoryOnly: true)
        s.set(.local, ["a": 1, "b": "two"])
        XCTAssertEqual(s.get(.local, "a")["a"] as? Int, 1)
        XCTAssertEqual(s.get(.local, ["a", "b"]).count, 2)
        s.remove(.local, "a")
        XCTAssertNil(s.get(.local, "a")["a"])
        s.clear(.local)
        XCTAssertTrue(s.get(.local, nil).isEmpty)
    }

    func testStorageGetWithDefaults() {
        let s = ExtensionStorage(inMemoryOnly: true)
        s.set(.local, ["present": 9])
        let r = s.get(.local, ["present": 0, "absent": 42])
        XCTAssertEqual(r["present"] as? Int, 9)
        XCTAssertEqual(r["absent"] as? Int, 42)
    }

    func testStorageSessionResetsButLocalPersists() throws {
        // storage.local persists across a fresh instance (simulated restart);
        // storage.session is per-instance.
        let key = "persist_test_\(UUID().uuidString)"
        let a = ExtensionStorage()
        a.set(.local, [key: "kept"])
        a.set(.session, [key: "ephemeral"])
        let b = ExtensionStorage()
        XCTAssertEqual(b.get(.local, key)[key] as? String, "kept", "local must survive restart")
        XCTAssertNil(b.get(.session, key)[key], "session must not survive restart")
        b.remove(.local, key) // cleanup
    }

    func testStorageAtRestIsEncrypted() throws {
        let key = "enc_test_\(UUID().uuidString)"
        let marker = "PLAINTEXT_MARKER_\(UUID().uuidString)"
        let s = ExtensionStorage()
        s.set(.local, [key: marker])
        let fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Muninn/storage.local.enc")
        let raw = (try? Data(contentsOf: fileURL)) ?? Data()
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains(marker), "value must not be plaintext on disk")
        s.remove(.local, key)
    }

    // MARK: - alarms

    func testAlarmFires() async {
        let reg = AlarmRegistry()
        let exp = expectation(description: "alarm fires")
        reg.onFire = { a in if a.name == "t" { exp.fulfill() } }
        reg.create(name: "t", info: ["delayInMinutes": 0.02])
        await fulfillment(of: [exp], timeout: 5)
    }

    func testAlarmClear() {
        let reg = AlarmRegistry()
        reg.create(name: "x", info: ["delayInMinutes": 5])
        XCTAssertNotNil(reg.get(name: "x"))
        XCTAssertTrue(reg.clear(name: "x"))
        XCTAssertNil(reg.get(name: "x"))
    }

    // MARK: - broker dispatch

    private func broker() -> MessageBroker {
        MessageBroker(storage: ExtensionStorage(inMemoryOnly: true))
    }

    func testBrokerStorageRoundTrip() throws {
        let b = broker()
        _ = try b.handle(["ns": "storage", "method": "local.set", "args": [["k": "v"]]])
        let r = try b.handle(["ns": "storage", "method": "local.get", "args": ["k"]])
        XCTAssertEqual((r as? [String: Any])?["k"] as? String, "v")
    }

    func testBrokerTruthfulMinimums() throws {
        let b = broker()
        XCTAssertEqual((try b.handle(["ns": "tabs", "method": "query", "args": []]) as? [Any])?.count, 0)
        XCTAssertEqual((try b.handle(["ns": "permissions", "method": "contains", "args": []]) as? Bool), true)
        XCTAssertNoThrow(try b.handle(["ns": "action", "method": "setBadgeText", "args": [["text": "3"]]]))
        XCTAssertEqual(b.badgeText, "3")
    }

    func testNativeMessagingIsBenignButRejects() {
        let b = broker()
        XCTAssertThrowsError(try b.handle(["ns": "runtime", "method": "connectNative", "args": ["x"]]))
        XCTAssertTrue(b.auditLog.contains { $0["kind"] as? String == "nativeMessaging-noop" })
    }

    func testUnmodelledAccessIsAuditedNotSilent() {
        let b = broker()
        XCTAssertThrowsError(try b.handle(["ns": "weirdns", "method": "weirdmethod", "args": []]))
        XCTAssertTrue(b.auditLog.contains { ($0["ns"] as? String) == "weirdns" })
    }

    func testPayloadOpacity() {
        let b = broker()
        let secret = "SENTINEL_\(UUID().uuidString)"
        _ = try? b.handle(["ns": "storage", "method": "local.set", "args": [["s": secret]]])
        // The stored value must never appear in any audit/log surface.
        XCTAssertFalse(String(describing: b.auditLog).contains(secret))
    }
}
