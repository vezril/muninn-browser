import Foundation

/// A recorded in-app notification (the text of a toast that was shown).
struct AppNotification: Codable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var date: Date = Date()
}

/// How long notifications are kept before auto-clearing.
enum NotificationRetention: String, CaseIterable {
    case h1, h6, d1, d7, never

    var displayName: String {
        switch self {
        case .h1:    return "1 Hour"
        case .h6:    return "6 Hours"
        case .d1:    return "1 Day"
        case .d7:    return "7 Days"
        case .never: return "Until Cleared"
        }
    }
    /// Max age, or nil to keep until manually cleared.
    var interval: TimeInterval? {
        switch self {
        case .h1:    return 3600
        case .h6:    return 6 * 3600
        case .d1:    return 24 * 3600
        case .d7:    return 7 * 24 * 3600
        case .never: return nil
        }
    }

    static var current: NotificationRetention {
        get { NotificationRetention(rawValue: UserDefaults.standard.string(forKey: "muninn.notifRetention") ?? "") ?? .d1 }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "muninn.notifRetention") }
    }
}

/// Persists shown notifications (newest first) so a missed toast can be reviewed in the Tools
/// sidebar. Auto-prunes past the retention window; also clearable manually.
@MainActor
final class NotificationStore {
    private(set) var items: [AppNotification] = []
    var onChange: (() -> Void)?

    private let fileURL: URL

    init() {
        let base = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory).appendingPathComponent("Muninn", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("notifications.json")
        items = load()
        prune()
    }

    func add(_ text: String) {
        items.insert(AppNotification(text: text), at: 0)
        prune(); save(); onChange?()
    }

    func clear() { items.removeAll(); save(); onChange?() }

    /// Drop notifications older than the retention window (nil interval → keep all).
    func prune() {
        guard let interval = NotificationRetention.current.interval else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        let before = items.count
        items.removeAll { $0.date < cutoff }
        if items.count != before { save() }
    }

    private func load() -> [AppNotification] {
        guard let data = try? Data(contentsOf: fileURL),
              let n = try? JSONDecoder().decode([AppNotification].self, from: data) else { return [] }
        return n
    }
    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: fileURL, options: .atomic) }
    }
}
