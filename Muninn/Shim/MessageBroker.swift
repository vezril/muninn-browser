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

    /// Named push contexts (ADR-007 / E6 message bus). `host` = the background
    /// Worker (reached via its page's MAIN-world `window.__shimPush` → worker);
    /// `page` = a tab's isolated content world (reached via
    /// `evaluateJavaScript(…, in: world)` → content-shim `__muninnContentPush`).
    private struct PushContext { weak var webView: WKWebView?; let world: WKContentWorld? }
    private var contexts: [String: PushContext] = [:]

    /// Boxes a JS-value response so the continuation type is Sendable; every
    /// access is main-actor-confined, so unchecked is sound.
    private struct AnyBox: @unchecked Sendable { let value: Any? }

    /// Parked continuations for cross-context request/response (correlation id → cont).
    private var pending: [String: CheckedContinuation<AnyBox, Never>] = [:]
    private var respSeq = 0

    /// Badge state recorded for the future toolbar (no toolbar yet).
    private(set) var badgeText: String = ""

    init(storage: ExtensionStorage = ExtensionStorage()) {
        self.storage = storage
        super.init()
        alarms.onFire = { [weak self] alarm in
            self?.pushEvent(key: "alarms.onAlarm", args: [[
                "name": alarm.name, "scheduledTime": alarm.scheduledTime,
            ]], to: "host")
        }
    }

    // MARK: - context registry

    func registerContext(_ name: String, webView: WKWebView, world: WKContentWorld?) {
        contexts[name] = PushContext(webView: webView, world: world)
    }
    func unregisterContext(_ name: String) { contexts[name] = nil }

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
        case "windows": return windowsCall(method, args)
        case "action": return actionCall(method, args)
        case "clipboardWrite": return clipboardCall(args)
        case "permissions", "scripting", "webNavigation":
            // Truthful-minimum stubs; real behavior arrives with E5/E9.
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
            if let items = args.first as? [String: Any] {
                let before = storage.get(area, Array(items.keys))
                storage.set(area, items)
                var changes: [String: Any] = [:]
                for (k, v) in items {
                    var c: [String: Any] = ["newValue": v]
                    if let old = before[k] { c["oldValue"] = old }
                    changes[k] = c
                }
                fireStorageChanged(area: parts[0], changes: changes)
            }
            return NSNull()
        case "remove":
            let keys: [String] = (args.first as? String).map { [$0] } ?? (args.first as? [String]) ?? []
            let before = storage.get(area, keys)
            storage.remove(area, args.first)
            var changes: [String: Any] = [:]
            for k in keys where before[k] != nil { changes[k] = ["oldValue": before[k]!] }
            fireStorageChanged(area: parts[0], changes: changes)
            return NSNull()
        case "clear":
            let before = storage.get(area, nil)
            storage.clear(area)
            var changes: [String: Any] = [:]
            for (k, v) in before { changes[k] = ["oldValue": v] }
            fireStorageChanged(area: parts[0], changes: changes)
            return NSNull()
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
            // A self-service sendMessage from the host worker with no other peer
            // resolves to undefined. Page-origin sendMessage is routed through the
            // ASYNC cross-context path (routeSendMessageToHost), not here.
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

    /// Set by the shell — navigates its one tab when the extension opens a URL
    /// (the auth-fork is background-driven via tabs.create/update, E6 finding).
    var onOpenURL: ((URL, _ active: Bool) -> Void)?

    private func tabsCall(_ method: String, _ args: [Any]) -> Any? {
        switch method {
        case "query": return [] as [Any]          // single-tab shell (E9 adds the model)
        case "getCurrent", "get": return ["id": 1, "active": true]
        case "create", "update":
            if let d = args.first as? [String: Any], let urlStr = d["url"] as? String {
                openURL(urlStr, member: method)
            } else if args.count > 1, let d = args[1] as? [String: Any], let urlStr = d["url"] as? String {
                openURL(urlStr, member: method) // tabs.update(tabId, {url})
            }
            return ["id": 1, "active": true]
        case "remove", "reload", "sendMessage": return NSNull()
        default: record(ns: "tabs", member: method, kind: "call"); return NSNull()
        }
    }

    private func windowsCall(_ method: String, _ args: [Any]) -> Any? {
        if method == "create", let d = args.first as? [String: Any] {
            if let urlStr = d["url"] as? String { openURL(urlStr, member: "windows.create") }
            else if let urls = d["url"] as? [String], let first = urls.first { openURL(first, member: "windows.create") }
        }
        return ["id": 1]
    }

    /// Drive the shell's tab. Records only host+path (never the query string,
    /// which carries the one-time fork `state` nonce) — ground rule 1.
    private func openURL(_ urlStr: String, member: String) {
        guard let url = URL(string: urlStr) else { return }
        let label = (url.host ?? "?") + url.path
        record(ns: "tabs", member: member, kind: "open-url", extra: ["url": label])
        onOpenURL?(url, true)
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

    private func fireStorageChanged(area: String, changes: [String: Any]) {
        guard !changes.isEmpty else { return }
        pushEvent(key: "storage.onChanged", args: [changes, area], to: "host")
    }

    // MARK: - cross-context request/response bus (E6, design Decision 2)

    /// Page-origin `runtime.sendMessage` → deliver to the host worker's
    /// `onMessage` listeners (background.js) and await `sendResponse`. This
    /// delivery is the auth-fork login pickup.
    /// E6 human-gate observation only: a **payload-free** signal that a page→host
    /// relay/response occurred (ground rule 1 — never carries message content or
    /// tokens, only direction + sender host + timing). Set solely in the gate run.
    var onCrossContextRelay: ((_ direction: String, _ senderHost: String) -> Void)?

    func routeSendMessageToHost(_ message: Any?, senderURL: String?) async -> Any? {
        guard contexts["host"] != nil else { return NSNull() }
        let senderHost = senderURL.flatMap { URL(string: $0)?.host } ?? "?"
        onCrossContextRelay?("relay-in", senderHost)
        respSeq += 1
        let id = "resp\(respSeq)"
        let sender: [String: Any] = [
            "id": PassBundle.canonicalID, "url": senderURL ?? "",
            "frameId": 0, "tab": ["id": 1, "url": senderURL ?? ""],
        ]
        let env: [String: Any] = [
            "__shim": "push", "key": "runtime.onMessage",
            "args": [message ?? NSNull(), sender], "respId": id,
        ]
        let box = await withCheckedContinuation { (cont: CheckedContinuation<AnyBox, Never>) in
            pending[id] = cont
            deliver(env, to: "host")
            // Safety valve: if the worker never responds, resolve undefined.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                if let c = self?.pending.removeValue(forKey: id) { c.resume(returning: AnyBox(value: NSNull())) }
            }
        }
        onCrossContextRelay?("response-out", senderHost) // background.js handled it
        return box.value
    }

    /// Called when a worker's `sendResponse` comes back through the host relay.
    func resolveResponse(id: String, result: Any?) {
        if let cont = pending.removeValue(forKey: id) { cont.resume(returning: AnyBox(value: result ?? NSNull())) }
    }

    /// Fire the extension lifecycle event so background.js runs its install /
    /// startup hooks (the install hook drives the auth-fork onboarding URL).
    func fireExtensionLifecycle(firstRun: Bool) {
        if firstRun {
            pushEvent(key: "runtime.onInstalled", args: [["reason": "install", "temporary": false]], to: "host")
        } else {
            pushEvent(key: "runtime.onStartup", args: [], to: "host")
        }
    }

    /// Push an event into a specific named context (no broadcast).
    func pushEvent(key: String, args: [Any], to context: String) {
        deliver(["__shim": "push", "key": key, "args": args], to: context)
    }

    private func deliver(_ env: [String: Any], to name: String) {
        guard let ctx = contexts[name], let webView = ctx.webView,
              let data = try? JSONSerialization.data(withJSONObject: env),
              let json = String(data: data, encoding: .utf8) else { return }
        if let world = ctx.world {
            // page isolated world → content-shim's __muninnContentPush
            webView.evaluateJavaScript("__muninnContentPush(\(json))", in: nil, in: world)
        } else {
            // host page MAIN world → __shimPush → worker
            webView.evaluateJavaScript("window.__shimPush(\(json))")
        }
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
