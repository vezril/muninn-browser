import Foundation
import WebKit
import AppKit

/// Native hub for the shim (ADR-007). Every `browser.*` call the shim makes
/// arrives here as an envelope and is dispatched to a Tier-1 handler; events
/// (alarms firing, future onMessage delivery) are pushed back out through the
/// host page's `window.__shimPush`.
///
/// Runs on the main actor: WebKit interop is main-thread, and main-actor
/// serialization gives the per-context ordering ADR-007 requires for free
/// (hub-and-spoke, no JS↔JS path). Message payloads are treated as opaque —
/// only envelope fields are read, logged, or routed (FR-21/NFR-8).
@MainActor
final class MessageBroker: NSObject {
    let storage: ExtensionStorage
    let alarms = AlarmRegistry()

    /// Audit sink — every unmodelled access + host lifecycle event lands here.
    private(set) var auditLog: [[String: Any]] = []
    var onAudit: (([String: Any]) -> Void)?

    /// The host page we push events into (set by BackgroundHost once loaded).
    weak var eventTarget: WKWebView?

    /// Badge state recorded for the future toolbar (no toolbar yet).
    private(set) var badgeText: String = ""

    init(storage: ExtensionStorage = ExtensionStorage()) {
        self.storage = storage
        super.init()
        alarms.onFire = { [weak self] alarm in
            self?.pushEvent(key: "alarms.onAlarm", args: [[
                "name": alarm.name, "scheduledTime": alarm.scheduledTime,
            ]])
        }
    }

    // MARK: - dispatch

    /// Returns a JS-convertible result, or throws with a message the shim
    /// surfaces as `lastError`. Synchronous: all Tier-1 operations are
    /// main-thread-local, and synchronous dispatch keeps the WebKit reply
    /// handler boundary clean under Swift 6 concurrency.
    func handle(_ env: [String: Any]) throws -> Any? {
        guard let ns = env["ns"] as? String, let method = env["method"] as? String else {
            throw ShimError("malformed envelope")
        }
        let args = env["args"] as? [Any] ?? []

        switch ns {
        case "storage": return try storageCall(method, args)
        case "alarms": return alarmsCall(method, args)
        case "runtime": return try runtimeCall(method, args)
        case "tabs": return tabsCall(method, args)
        case "action": return actionCall(method, args)
        case "clipboardWrite": return clipboardCall(args)
        case "windows", "permissions", "scripting", "webNavigation":
            // Truthful-minimum stubs; real behavior arrives with E5/E6/E9.
            return stubbed(ns: ns, method: method)
        default:
            record(ns: ns, member: method, kind: "unhandled-namespace")
            throw ShimError("unmodelled \(ns).\(method)")
        }
    }

    private func storageCall(_ method: String, _ args: [Any]) throws -> Any? {
        // method is "<area>.<op>", e.g. "local.get"
        let parts = method.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let area = ExtensionStorage.Area(rawValue: parts[0]) else {
            throw ShimError("bad storage method \(method)")
        }
        switch parts[1] {
        case "get": return storage.get(area, args.first)
        case "set":
            if let items = args.first as? [String: Any] { storage.set(area, items) }
            return NSNull()
        case "remove": storage.remove(area, args.first); return NSNull()
        case "clear": storage.clear(area); return NSNull()
        case "getBytesInUse": return 0
        default: record(ns: "storage", member: method, kind: "call"); throw ShimError("unmodelled storage.\(method)")
        }
    }

    private func alarmsCall(_ method: String, _ args: [Any]) -> Any? {
        switch method {
        case "create":
            let name = (args.first as? String) ?? ((args.first as? [String: Any])?["name"] as? String) ?? ""
            let info = (args.count > 1 ? args[1] : args.first) as? [String: Any] ?? [:]
            alarms.create(name: name, info: info); return NSNull()
        case "get": return alarms.get(name: (args.first as? String) ?? "") ?? NSNull()
        case "getAll": return alarms.getAll()
        case "clear": return alarms.clear(name: (args.first as? String) ?? "")
        case "clearAll": alarms.clearAll(); return true
        default: return NSNull()
        }
    }

    private func runtimeCall(_ method: String, _ args: [Any]) throws -> Any? {
        switch method {
        case "sendMessage":
            // No peer contexts yet (background host is alone until E6).
            // Resolve to undefined so senders don't hang; onMessage has no listeners elsewhere.
            return NSNull()
        case "getPlatformInfo": return ["os": "mac", "arch": "arm64"]
        case "getBrowserInfo": return ["name": "Muninn", "version": "0.1.0"]
        case "reload": return NSNull()
        case "requestUpdateCheck": return ["status": "no_update"]
        case "connectNative", "sendNativeMessage":
            // FR-12 benign no-op (nativeMessaging is a required Safari permission).
            record(ns: "runtime", member: method, kind: "nativeMessaging-noop")
            throw ShimError("nativeMessaging unavailable")
        case "setUninstallURL": return NSNull()
        case "connect":
            // Full port semantics land in task 3; boot should not need a live peer.
            record(ns: "runtime", member: method, kind: "connect-stub")
            throw ShimError("runtime.connect not yet modelled")
        default:
            record(ns: "runtime", member: method, kind: "call")
            throw ShimError("unmodelled runtime.\(method)")
        }
    }

    private func tabsCall(_ method: String, _ args: [Any]) -> Any? {
        switch method {
        case "query": return [] as [Any]          // no tabs exist yet
        case "getCurrent": return NSNull()
        case "create", "update", "get": return ["id": -1]
        case "remove", "reload", "sendMessage": return NSNull()
        default: record(ns: "tabs", member: method, kind: "call"); return NSNull()
        }
    }

    private func actionCall(_ method: String, _ args: [Any]) -> Any? {
        if method == "setBadgeText", let d = args.first as? [String: Any], let t = d["text"] as? String {
            badgeText = t
        }
        return NSNull() // records state for the future toolbar
    }

    private func clipboardCall(_ args: [Any]) -> Any? {
        if let text = args.first as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        return NSNull()
    }

    private func stubbed(ns: String, method: String) -> Any? {
        switch ns {
        case "permissions": return method == "contains" ? true : NSNull()
        case "webNavigation": return method == "getAllFrames" ? [] as [Any] : NSNull()
        default: return NSNull()
        }
    }

    // MARK: - events

    func pushEvent(key: String, args: [Any]) {
        guard let webView = eventTarget else { return }
        let env: [String: Any] = ["__shim": "push", "key": key, "args": args]
        guard let data = try? JSONSerialization.data(withJSONObject: env),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__shimPush(\(json))")
    }

    // MARK: - audit

    func record(ns: String, member: String, kind: String, extra: [String: Any] = [:]) {
        var entry: [String: Any] = ["ns": ns, "member": member, "kind": kind,
                                    "at": Date().timeIntervalSince1970]
        entry.merge(extra) { a, _ in a }
        auditLog.append(entry)
        onAudit?(entry)
    }

    struct ShimError: Error, CustomStringConvertible {
        let msg: String
        init(_ m: String) { msg = m }
        var description: String { msg }
    }
}
