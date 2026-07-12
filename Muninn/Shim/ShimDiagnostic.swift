import Foundation
import AppKit

/// Headless S1 boot harness. Activated by the `MUNINN_SHIM_DIAGNOSTIC` env var
/// so it can run from the command line with NO visible window (.prohibited
/// activation) — within ground rule 2. Boots the background host, lets it
/// settle, then writes the FR-7 global-scope audit artifact and exits.
///
/// Env:
///   MUNINN_SHIM_DIAGNOSTIC=1            enable
///   MUNINN_SHIM_SETTLE=<seconds>       settle window (default 12)
///   MUNINN_SHIM_AUDIT_OUT=<path>       artifact path (default: stdout only)
@MainActor
enum ShimDiagnostic {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["MUNINN_SHIM_DIAGNOSTIC"] != nil }

    private static var broker: MessageBroker?
    private static var host: BackgroundHost?

    private static var consoleLines: [String] = []

    static func run() {
        NSApp.setActivationPolicy(.prohibited)
        let env = ProcessInfo.processInfo.environment
        if env["MUNINN_SHIM_SCENARIOS"] != nil { runScenarios(); return }
        let settle = TimeInterval(env["MUNINN_SHIM_SETTLE"] ?? "") ?? 12

        guard PassBundle.isPresent else {
            FileHandle.standardError.write(Data("S1: PassBundle not embedded — cannot boot\n".utf8))
            exit(2)
        }

        let broker = MessageBroker()
        let host = BackgroundHost(broker: broker)
        self.broker = broker
        self.host = host

        host.onBootEvent = { entry in
            let kind = entry["kind"] as? String ?? "?"
            if kind == "console" {
                print("  [worker:\(entry["level"] ?? "log")] \(entry["text"] ?? "")")
            } else {
                print("  [\(kind)] \(compact(entry))")
            }
        }

        print("S1 boot — Pass v\(PassBundle.version), settling \(Int(settle))s…")
        host.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
            finish(env: env)
        }
    }

    private static func finish(env: [String: String]) {
        guard let host, let broker else { exit(3) }
        let ok = host.bootSucceeded && !host.hasErrors
        print("\nS1 result: \(ok ? "CLEAN" : "ISSUES") — backgroundLoaded=\(host.bootSucceeded) errors=\(host.hasErrors)")
        print("Audit entries: \(broker.auditLog.count)  Boot events: \(host.bootLog.count)")

        if let out = env["MUNINN_SHIM_AUDIT_OUT"] {
            let md = renderArtifact(host: host, broker: broker, clean: ok)
            try? md.write(toFile: out, atomically: true, encoding: .utf8)
            print("Wrote \(out)")
        }
        host.stop()
        exit(ok ? 0 : 1)
    }

    // MARK: - scenario self-test (headless, execution-grounded)

    private static let secret = "SENTINEL_TOPSECRET_42"

    static func runScenarios() {
        guard PassBundle.isPresent else { exit(2) }
        let broker = MessageBroker()
        let host = BackgroundHost(broker: broker)
        self.broker = broker; self.host = host

        host.onBootEvent = { entry in
            if entry["kind"] as? String == "console", let t = entry["text"] as? String {
                consoleLines.append(t)
            }
        }
        host.start()

        // Wait for boot, then inject scenarios.
        waitUntil({ host.bootSucceeded }, timeout: 15) {
            let scenarios: [String] = [
                // round-trip: worker -> page -> native broker -> back
                "browser.storage.local.set({__scn:'v1'}).then(function(){return browser.storage.local.get('__scn')}).then(function(r){console.log('SCN storage-roundtrip '+(r.__scn==='v1'?'PASS':'FAIL'))}).catch(function(e){console.log('SCN storage-roundtrip FAIL '+e)})",
                // event push: native alarm -> worker listener
                "browser.alarms.onAlarm.addListener(function(a){if(a.name==='__scnA')console.log('SCN alarm-fire PASS')});browser.alarms.create('__scnA',{delayInMinutes:0.02})",
                // sendMessage must resolve/reject, never hang
                "browser.runtime.sendMessage({p:1}).then(function(){console.log('SCN sendmessage PASS')},function(){console.log('SCN sendmessage PASS')})",
                // nativeMessaging benign (no throw at access)
                "try{var p=browser.runtime.connectNative('x');(p&&p.then)?p.then(function(){console.log('SCN nativemsg PASS')},function(){console.log('SCN nativemsg PASS')}):console.log('SCN nativemsg PASS')}catch(e){console.log('SCN nativemsg FAIL '+e)}",
                // opacity: store a secret; native must never log its bytes
                "browser.storage.local.set({__secret:'\(secret)'}).then(function(){console.log('SCN opacity-setup done')})",
            ]
            for s in scenarios { host.evalInWorker(s) }

            // Give async scenarios (alarm ~1.2s) time, then assert.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { finishScenarios(broker: broker, host: host) }
        }
    }

    private static func finishScenarios(broker: MessageBroker, host: BackgroundHost) {
        var results: [(String, Bool)] = []
        func sawPass(_ name: String) -> Bool { consoleLines.contains { $0 == "SCN \(name) PASS" } }

        results.append(("broker-round-trip", sawPass("storage-roundtrip")))
        results.append(("alarm-event-push", sawPass("alarm-fire")))
        results.append(("sendMessage-no-hang", sawPass("sendmessage")))
        results.append(("nativeMessaging-benign", sawPass("nativemsg")))

        // Native: storage persists across a simulated host/storage restart.
        let persistKey = "__persist_scn"
        let s1 = ExtensionStorage()
        s1.set(.local, [persistKey: "p1"])
        let s2 = ExtensionStorage() // re-reads the encrypted file
        let persisted = (s2.get(.local, persistKey)[persistKey] as? String) == "p1"
        s2.remove(.local, persistKey)
        results.append(("storage-persists-across-restart", persisted))

        // Payload opacity: the secret we stored must not appear in ANY native
        // log surface (broker audit, boot log, captured console).
        let haystack = (consoleLines.joined(separator: "\n"))
            + String(describing: broker.auditLog) + String(describing: host.bootLog)
        results.append(("payload-opacity", !haystack.contains(secret)))

        print("\n=== e2-e3 scenario results ===")
        var allPass = true
        for (name, ok) in results {
            print("  \(ok ? "PASS" : "FAIL")  \(name)")
            allPass = allPass && ok
        }
        print(allPass ? "\nALL SCENARIOS PASS" : "\nSCENARIO FAILURES PRESENT")
        host.stop()
        exit(allPass ? 0 : 1)
    }

    private static func waitUntil(_ cond: @escaping () -> Bool, timeout: TimeInterval,
                                  then: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if cond() { then(); return }
            if Date() > deadline { print("boot timeout"); host?.stop(); exit(4) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { poll() }
        }
        poll()
    }

    private static func compact(_ d: [String: Any]) -> String {
        d.filter { $0.key != "kind" && $0.key != "at" }
         .map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
    }

    private static func renderArtifact(host: BackgroundHost, broker: MessageBroker, clean: Bool) -> String {
        let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
        var s = "# S1 — background.js global-scope audit — \(date)\n\n"
        s += "- Pass bundle version: `\(PassBundle.version)`\n"
        s += "- Result: **\(clean ? "CLEAN" : "ISSUES")** (backgroundLoaded=\(host.bootSucceeded), errors=\(host.hasErrors))\n\n"

        // Group unmodelled API accesses (the real FR-7 finding surface).
        var byMember: [String: Int] = [:]
        for e in broker.auditLog {
            let key = "\(e["ns"] ?? "?").\(e["member"] ?? "?") (\(e["kind"] ?? "?"))"
            byMember[key, default: 0] += 1
        }
        s += "## Unmodelled / audited API accesses\n\n"
        if byMember.isEmpty { s += "_none_\n\n" }
        else {
            s += "| API | kind | count | triage |\n|---|---|---|---|\n"
            for (k, n) in byMember.sorted(by: { $0.key < $1.key }) {
                let parts = k.components(separatedBy: " (")
                let api = parts[0]; let kind = parts.count > 1 ? parts[1].replacingOccurrences(of: ")", with: "") : ""
                s += "| `\(api)` | \(kind) | \(n) | _TODO_ |\n"
            }
            s += "\n"
        }

        s += "## Worker errors / rejections\n\n"
        let errs = host.bootLog.filter { ["workerError", "workerRejection"].contains($0["kind"] as? String ?? "") }
        if errs.isEmpty { s += "_none_\n\n" }
        else { for e in errs { s += "- `\(e["kind"] ?? "?")`: \(e["message"] ?? "")\n" }; s += "\n" }

        s += "## Boot event timeline\n\n```\n"
        for e in host.bootLog where (e["kind"] as? String) != "console" {
            s += "\(e["kind"] ?? "?") \(compact(e))\n"
        }
        s += "```\n\n## Triage\n\n_Every audited entry needs a Tier 1/2/3 disposition before E8 (FR-7)._\n"
        return s
    }
}
