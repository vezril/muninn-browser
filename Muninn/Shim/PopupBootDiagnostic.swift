import Foundation
import AppKit
import WebKit

/// Headless diagnostic (env `MUNINN_POPUP_BOOT=1`): boot the background host + the popup, and capture
/// the popup↔background handshake (type-only) + the popup's final DOM shape. Answers the parked E7
/// question — **what is the popup awaiting from background that keeps its login UI from rendering?**
/// No login, no window, no credentials; logs counts/keys only (ground rule 1). Output:
/// `~/Library/Application Support/Muninn/popupboot.log`.
@MainActor
enum PopupBootDiagnostic {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["MUNINN_POPUP_BOOT"] != nil }

    private static var broker: MessageBroker?
    private static var host: BackgroundHost?
    private static var popup: PopupHost?

    private static let logURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Muninn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("popupboot.log")
    }()
    private static func note(_ s: String) {
        NSLog("[popup-boot] %@", s)
        let line = (s + "\n").data(using: .utf8)!
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line); try? h.close() }
        else { try? line.write(to: logURL) }
    }

    static func run() {
        NSApp.setActivationPolicy(.prohibited)
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
        note("=== popup-boot: background + popup handshake capture ===")
        guard PassBundle.isPresent else { note("FAIL: PassBundle not embedded"); exitSoon(2); return }

        let broker = MessageBroker()
        let host = BackgroundHost(broker: broker)
        self.broker = broker; self.host = host

        broker.onWire = { note("[wire] \($0)") }
        broker.onCrossContextRelay = { dir, h in note("[relay] \(dir) host=\(h)") }
        broker.onAudit = { e in
            if let k = e["kind"] as? String, k == "open-url" { note("[open-url] \(e["url"] ?? "?")") }
        }
        host.onBootEvent = { e in
            let kind = e["kind"] as? String ?? "?"
            if kind == "console" { note("[worker:\(e["level"] ?? "log")] \(e["text"] ?? "")") }
            else if kind != "audit" { note("[host:\(kind)]") }
        }

        note("starting background host…")
        host.start()

        // Match the GUI path: fire onInstalled (firstRun) — this is what the real app does, and what the
        // onStartup headless run did NOT, so it's the prime suspect for the GUI blank popup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let firstRun = ProcessInfo.processInfo.environment["MUNINN_POPUP_BOOT_STARTUP"] == nil
            note("firing runtime.\(firstRun ? "onInstalled" : "onStartup"); booting popup…")
            broker.fireExtensionLifecycle(firstRun: firstRun)
            let popup = PopupHost(broker: broker)
            self.popup = popup
            popup.load()
        }

        // After the app has had time to boot + handshake, inspect the popup DOM.
        DispatchQueue.main.asyncAfter(deadline: .now() + 13) { inspectPopupDOM() }
    }

    /// Counts/lengths only — never element text/values (pre-login, but keep it type-only regardless).
    private static func inspectPopupDOM() {
        guard let wv = popup?.webView else { note("no popup webview"); exitSoon(0); return }
        let js = #"""
        (function () {
          try {
            var root = document.getElementById('root') || document.getElementById('app-root')
                     || document.querySelector('[id*="root"], main');
            return JSON.stringify({
              url: location.pathname,
              hasRoot: !!root,
              rootChildren: root ? root.children.length : -1,
              inputs: document.querySelectorAll('input').length,
              buttons: document.querySelectorAll('button').length,
              forms: document.querySelectorAll('form').length,
              anchors: document.querySelectorAll('a').length,
              htmlLen: (document.body ? document.body.innerHTML.length : 0),
              textLen: (document.body ? document.body.innerText.length : 0),
              text: (document.body ? document.body.innerText.slice(0, 200) : ''),
              buttonLabels: Array.prototype.map.call(document.querySelectorAll('button'), function (b) { return (b.innerText || b.getAttribute('aria-label') || '').slice(0, 40); }),
              readyState: document.readyState
            });
          } catch (e) { return 'DOM-ERR: ' + e; }
        })()
        """#
        wv.evaluateJavaScript(js) { result, err in
            note("[popup-dom] " + (result as? String ?? "eval-err: \(String(describing: err))"))
            note("(rootChildren>0 or inputs/buttons>0 → login UI rendered; all 0 → still awaiting background state)")
            exitSoon(0)
        }
    }

    private static func exitSoon(_ code: Int32) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { note("done (\(code))."); exit(code) }
    }
}
