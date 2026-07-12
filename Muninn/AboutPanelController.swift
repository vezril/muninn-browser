import AppKit

/// FR-26: displays the vendored Pass extension version pin and the date of the
/// most recent FR-25 re-grep artifact. Values are copied into the app bundle at
/// build time ("Embed About Metadata" build phase) from vendor/pass-extension/
/// MANIFEST.lock and research/regrep/.
@MainActor
final class AboutPanelController {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let text = NSTextView()
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.string = Self.metadataSummary()
        text.textContainerInset = NSSize(width: 12, height: 12)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 260))
        scroll.documentView = text
        scroll.hasVerticalScroller = true

        let window = NSWindow(
            contentRect: scroll.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Muninn"
        window.contentView = scroll
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    /// Renders MANIFEST.lock (JSON) and the latest re-grep date as plain text.
    static func metadataSummary() -> String {
        var lines = ["Muninn — development build", ""]

        if let url = Bundle.main.url(forResource: "MANIFEST", withExtension: "lock"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            lines.append("Vendored Proton Pass extension (FR-26):")
            for key in json.keys.sorted() {
                lines.append("  \(key): \(json[key] ?? "?")")
            }
        } else {
            lines.append("Vendored Proton Pass extension: NOT VENDORED YET")
            lines.append("  (run tools/refresh-pass-bundle.sh — see ADR-001)")
        }

        lines.append("")

        if let url = Bundle.main.url(forResource: "RegrepLatest", withExtension: "txt"),
           let value = try? String(contentsOf: url, encoding: .utf8),
           !value.isEmpty, value != "none" {
            lines.append("Latest FR-25 re-grep artifact: \(value)")
        } else {
            lines.append("Latest FR-25 re-grep artifact: NONE — shim work is gated until one exists")
        }

        return lines.joined(separator: "\n")
    }
}
