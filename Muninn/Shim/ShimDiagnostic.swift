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
    private static var measAppMB: [Double] = []
    private static var measWebMB: [Double] = []

    static func run() {
        NSApp.setActivationPolicy(.prohibited)
        let env = ProcessInfo.processInfo.environment
        if env["MUNINN_SHIM_SCENARIOS"] != nil { runScenarios(); return }
        if env["MUNINN_SHIM_MEASURE"] != nil { runMeasure(); return }
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
        // Surface what background.js tries to open (tabs.create/update / windows.create)
        // — the auth-fork is background-driven (E6 finding). Host+path only.
        broker.onAudit = { entry in
            if (entry["kind"] as? String) == "open-url" {
                print("  [OPEN-URL] \(entry["member"] ?? "?") -> \(entry["url"] ?? "?")")
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

        host.start()

        // Wait for boot, then inject scenarios (results come back via __report).
        waitUntil({ host.bootSucceeded }, timeout: 15) {
            let scenarios: [String] = [
                // round-trip: worker -> page -> native broker -> back
                "browser.storage.local.set({__scn:'v1'}).then(function(){return browser.storage.local.get('__scn')}).then(function(r){self.__report('storage-roundtrip', r.__scn==='v1')}).catch(function(){self.__report('storage-roundtrip', false)})",
                // event push: native alarm -> worker listener
                "browser.alarms.onAlarm.addListener(function(a){if(a.name==='__scnA')self.__report('alarm-fire', true)});browser.alarms.create('__scnA',{delayInMinutes:0.02})",
                // sendMessage must resolve/reject, never hang
                "browser.runtime.sendMessage({p:1}).then(function(){self.__report('sendmessage', true)},function(){self.__report('sendmessage', true)})",
                // nativeMessaging benign (no throw at access)
                "try{var p=browser.runtime.connectNative('x');(p&&p.then)?p.then(function(){self.__report('nativemsg', true)},function(){self.__report('nativemsg', true)}):self.__report('nativemsg', true)}catch(e){self.__report('nativemsg', false)}",
                // opacity: store a secret; native must never log its bytes
                "browser.storage.local.set({__secret:'\(secret)'}).then(function(){self.__report('opacity-setup', true)})",
            ]
            for s in scenarios { host.evalInWorker(s) }

            // Give async scenarios (alarm ~1.2s) time, then assert.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { finishScenarios(broker: broker, host: host) }
        }
    }

    private static func finishScenarios(broker: MessageBroker, host: BackgroundHost) {
        var results: [(String, Bool)] = []
        func sawPass(_ name: String) -> Bool {
            host.bootLog.contains {
                ($0["kind"] as? String) == "scenario" && ($0["name"] as? String) == name && ($0["ok"] as? Bool) == true
            }
        }

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

    // MARK: - NFR-10 residency measurement (headless, non-binding here; E11 binds)

    static func runMeasure() {
        guard PassBundle.isPresent else { exit(2) }
        let env = ProcessInfo.processInfo.environment
        let secs = TimeInterval(env["MUNINN_SHIM_MEASURE_SECS"] ?? "") ?? 300
        let broker = MessageBroker(); let host = BackgroundHost(broker: broker)
        self.broker = broker; self.host = host
        host.start()

        measAppMB = []; measWebMB = []
        waitUntil({ host.bootSucceeded }, timeout: 20) {
            print("NFR-10 measurement — idle \(Int(secs))s, sampling every 15s…")
            // JS timer fidelity in the hidden worker (ADR-005 throttling check).
            host.evalInWorker("self.__mtick=0;setInterval(function(){self.__mtick++},1000)")
            let n = max(1, Int(secs / 15))
            // Runs on DispatchQueue.main; assumeIsolated to reach @MainActor state
            // from this nonisolated local function.
            func sample(_ remaining: Int) {
                MainActor.assumeIsolated {
                    measAppMB.append(appFootprintMB()); measWebMB.append(webContentRSSMB(host: host))
                    if remaining <= 0 {
                        host.evalInWorker("self.__report('ticks', true, self.__mtick)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            MainActor.assumeIsolated {
                                finishMeasure(host: host, appMB: measAppMB, webMB: measWebMB, secs: secs, env: env)
                            }
                        }
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { sample(remaining - 1) }
                }
            }
            sample(n)
        }
    }

    private static func finishMeasure(host: BackgroundHost, appMB: [Double], webMB: [Double],
                                      secs: TimeInterval, env: [String: String]) {
        let ticks = host.bootLog.first { ($0["kind"] as? String) == "scenario" && ($0["name"] as? String) == "ticks" }?["value"] as? Int
        let expectedTicks = Int(secs)
        let appPeak = appMB.max() ?? 0, appAvg = appMB.isEmpty ? 0 : appMB.reduce(0, +) / Double(appMB.count)
        let webPeak = webMB.max() ?? 0, webAvg = webMB.isEmpty ? 0 : webMB.reduce(0, +) / Double(webMB.count)

        func f(_ d: Double) -> String { String(format: "%.1f", d) }
        print("\n=== NFR-10 residency (idle \(Int(secs))s) ===")
        print("  App process phys_footprint: avg \(f(appAvg)) MB, peak \(f(appPeak)) MB")
        print("  WebContent (host) RSS:      avg \(f(webAvg)) MB, peak \(f(webPeak)) MB")
        print("  JS timer ticks: \(ticks.map(String.init) ?? "?") of ~\(expectedTicks) expected (1/s)")
        print("  NFR-10 host ≤150 MB: \(webPeak <= 150 ? "PASS" : "CHECK") (WebContent peak)")
        print("  NFR-3 total ≤400 MB: \((appPeak + webPeak) <= 400 ? "PASS" : "CHECK") (app+host peak)")

        if let out = env["MUNINN_SHIM_MEASURE_OUT"] {
            let md = """
            # NFR-10 residency measurement — Pass v\(PassBundle.version)

            Headless idle run, \(Int(secs))s, sampled every 15s (non-binding here; E11 binds at 30 min).

            | metric | avg | peak | target |
            |---|---|---|---|
            | App process phys_footprint | \(f(appAvg)) MB | \(f(appPeak)) MB | (NFR-3 total ≤400 MB) |
            | WebContent (background host) RSS | \(f(webAvg)) MB | \(f(webPeak)) MB | NFR-10 ≤150 MB |

            - JS timer fidelity (hidden worker): **\(ticks.map(String.init) ?? "?")** ticks vs ~\(expectedTicks) expected (1/s) — throttling check (ADR-005).
            - NFR-10 (host ≤150 MB): **\(webPeak <= 150 ? "PASS" : "CHECK")**; NFR-3 (total ≤400 MB): **\((appPeak + webPeak) <= 400 ? "PASS" : "CHECK")**.
            - Window shortened to \(Int(secs))s for the e2-e3 change; the binding 30-min measurement is E11's.
            """
            try? md.write(toFile: out, atomically: true, encoding: .utf8)
            print("Wrote \(out)")
        }
        host.stop()
        exit(0)
    }

    private static func appFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576.0 : 0
    }

    private static func webContentRSSMB(host: BackgroundHost) -> Double {
        guard let wv = host.webView,
              let pid = (wv.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value, pid > 0 else { return 0 }
        let proc = Process(); proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-o", "rss=", "-p", "\(pid)"]
        let pipe = Pipe(); proc.standardOutput = pipe
        do { try proc.run() } catch { return 0 }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let kb = Double(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return kb / 1024.0
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
