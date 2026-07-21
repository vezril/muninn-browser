import AppKit

/// A key combo: a character plus modifier flags (masked to ⌃⌥⇧⌘).
struct Shortcut: Codable, Equatable {
    var key: String       // charactersIgnoringModifiers, lowercased (e.g. "n", ",")
    var modifiers: UInt   // NSEvent.ModifierFlags rawValue, masked

    static let mask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// Human display, e.g. "⌥⇧⌘C".
    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + (key == "," ? "," : key.uppercased())
    }
}

/// The remappable actions (workspace-switching ⌃1…⌃9 is fixed and not listed here).
enum ShortcutAction: String, CaseIterable {
    case commandBar, newTab, quickLook, closeTab, reopenClosed, togglePin
    case focusAddress, reload, copyURL, copyMarkdown, clearUnpinned, settings, toolsSidebar

    var title: String {
        switch self {
        case .commandBar:   return "Command Bar"
        case .newTab:       return "New Tab"
        case .quickLook:    return "Quick Look"
        case .closeTab:     return "Close Tab"
        case .reopenClosed: return "Reopen Closed Tab"
        case .togglePin:    return "Pin / Unpin Tab"
        case .focusAddress: return "Focus Address Bar"
        case .reload:       return "Reload"
        case .copyURL:      return "Copy URL"
        case .copyMarkdown: return "Copy as Markdown"
        case .clearUnpinned:return "Clear Unpinned Tabs"
        case .settings:     return "Settings"
        case .toolsSidebar: return "Toggle Tools Sidebar"
        }
    }

    var defaultShortcut: Shortcut {
        func s(_ k: String, _ m: NSEvent.ModifierFlags) -> Shortcut { Shortcut(key: k, modifiers: m.rawValue) }
        switch self {
        case .commandBar:   return s("n", [.command])
        case .newTab:       return s("t", [.command])
        case .quickLook:    return s("n", [.command, .option])
        case .closeTab:     return s("w", [.command])
        case .reopenClosed: return s("t", [.command, .shift])
        case .togglePin:    return s("d", [.command])
        case .focusAddress: return s("l", [.command])
        case .reload:       return s("r", [.command])
        case .copyURL:      return s("c", [.command, .shift])
        case .copyMarkdown: return s("c", [.command, .shift, .option])
        case .clearUnpinned:return s("k", [.command, .shift])
        case .settings:     return s(",", [.command])
        case .toolsSidebar: return s("t", [.command, .option])
        }
    }
}

/// Persisted shortcut overrides (falls back to each action's default).
enum ShortcutStore {
    private static func key(_ a: ShortcutAction) -> String { "muninn.shortcut." + a.rawValue }

    static func shortcut(for a: ShortcutAction) -> Shortcut {
        if let data = UserDefaults.standard.data(forKey: key(a)),
           let s = try? JSONDecoder().decode(Shortcut.self, from: data) { return s }
        return a.defaultShortcut
    }
    static func set(_ s: Shortcut?, for a: ShortcutAction) {
        if let s, let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: key(a)) }
        else { UserDefaults.standard.removeObject(forKey: key(a)) } // nil → reset to default
    }
    /// The action bound to a pressed combo, if any.
    static func action(key: String, modifiers: UInt) -> ShortcutAction? {
        ShortcutAction.allCases.first {
            let s = shortcut(for: $0); return s.key == key && s.modifiers == modifiers
        }
    }
}

/// A click-to-record shortcut field for the Settings window.
@MainActor
final class ShortcutRecorder: NSButton {
    var action_: ShortcutAction!
    var onChange: (() -> Void)?
    private var recording = false
    private var monitor: Any?

    func configure(_ a: ShortcutAction) {
        action_ = a
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        refresh()
    }

    override func mouseDown(with event: NSEvent) {
        recording ? stop() : start()
    }

    private func start() {
        recording = true; title = "Press keys…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 53 { self.stop(); return nil }                       // Esc → cancel
            if e.keyCode == 51 { ShortcutStore.set(nil, for: self.action_); self.stop(); return nil } // Delete → reset
            let flags = e.modifierFlags.intersection(Shortcut.mask)
            let key = (e.charactersIgnoringModifiers ?? "").lowercased()
            guard !key.isEmpty, !flags.isEmpty,
                  flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else { return nil }
            ShortcutStore.set(Shortcut(key: key, modifiers: flags.rawValue), for: self.action_)
            self.stop()
            return nil
        }
    }
    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        refresh(); onChange?()
    }
    private func refresh() { title = ShortcutStore.shortcut(for: action_).display }
}
