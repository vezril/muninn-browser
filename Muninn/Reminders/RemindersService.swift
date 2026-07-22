import AppKit
import EventKit

/// A reminder list (EventKit calendar of type `.reminder`).
struct ReminderList: Equatable {
    let id: String          // calendarIdentifier
    let title: String
    let color: NSColor?
}

/// A single reminder. Sendable so it can cross EventKit's background completion boundary.
struct ReminderItem: Sendable, Equatable {
    let id: String          // calendarItemIdentifier
    var title: String
    var notes: String?
    var completed: Bool
    var url: URL?
}

/// Thin EventKit wrapper for Apple Reminders — fully on-device, no shim. All reads/writes go through
/// the shared `EKEventStore`; mutations commit immediately and post `.EKEventStoreChanged`, which the
/// tool observes to refresh. Deployment target is macOS 15.4, so the modern full-access API is used.
///
/// NOT `@MainActor`: EventKit invokes `fetchReminders`' completion on its own background queue, so a
/// MainActor-isolated completion closure would trip a dispatch isolation assertion. `EKEventStore` is
/// safe to use across threads for these operations; the tool always calls in from the main thread.
final class RemindersService: @unchecked Sendable {
    static let shared = RemindersService()
    let store = EKEventStore()

    var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .reminder) }
    var authorized: Bool { status == .fullAccess }

    /// Prompt for (or confirm) full access. Returns whether we can read+write reminders.
    func requestAccess() async -> Bool {
        if authorized { return true }
        return (try? await store.requestFullAccessToReminders()) ?? false
    }

    // MARK: Lists

    func lists() -> [ReminderList] {
        store.calendars(for: .reminder)
            .map { ReminderList(id: $0.calendarIdentifier, title: $0.title, color: $0.color) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func defaultListId() -> String? { store.defaultCalendarForNewReminders()?.calendarIdentifier }

    private func calendar(_ id: String) -> EKCalendar? { store.calendar(withIdentifier: id) }

    /// Create a new reminder list. Inherits the default list's source (iCloud/local), else the first
    /// writable source. Returns the new list's id.
    @discardableResult
    func createList(named name: String) throws -> String {
        let cal = EKCalendar(for: .reminder, eventStore: store)
        cal.title = name
        cal.source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first
        try store.saveCalendar(cal, commit: true)
        return cal.calendarIdentifier
    }

    // MARK: Reminders

    /// Fetch a list's reminders (incomplete first). Mapping happens inside EventKit's completion so only
    /// Sendable `ReminderItem`s cross back to the main actor.
    func reminders(inListId id: String, includeCompleted: Bool) async -> [ReminderItem] {
        guard let cal = calendar(id) else { return [] }
        let predicate = store.predicateForReminders(in: [cal])
        return await withCheckedContinuation { (cont: CheckedContinuation<[ReminderItem], Never>) in
            store.fetchReminders(matching: predicate) { rems in
                let mapped: [ReminderItem] = (rems ?? [])
                    .filter { includeCompleted || !$0.isCompleted }
                    .map { r in
                        ReminderItem(id: r.calendarItemIdentifier, title: r.title ?? "",
                                     notes: r.notes, completed: r.isCompleted, url: r.url)
                    }
                let items = mapped.sorted { a, b -> Bool in
                    if a.completed != b.completed { return !a.completed }   // incomplete first
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                }
                cont.resume(returning: items)
            }
        }
    }

    @discardableResult
    func createReminder(title: String, notes: String? = nil, url: URL? = nil, inListId id: String?) throws -> String {
        let r = EKReminder(eventStore: store)
        r.title = title
        r.notes = notes
        if let url { r.url = url }
        r.calendar = id.flatMap { calendar($0) } ?? store.defaultCalendarForNewReminders()
        try store.save(r, commit: true)
        return r.calendarItemIdentifier
    }

    /// Add many reminders to one list in a single commit (used by page → list). Returns count saved.
    @discardableResult
    func addReminders(_ titles: [String], toListId id: String) throws -> Int {
        guard let cal = calendar(id) else { return 0 }
        var saved = 0
        for title in titles {
            let r = EKReminder(eventStore: store)
            r.title = title
            r.calendar = cal
            try store.save(r, commit: false)
            saved += 1
        }
        try store.commit()
        return saved
    }

    func setCompleted(_ completed: Bool, id: String) throws {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        r.isCompleted = completed
        try store.save(r, commit: true)
    }

    func update(id: String, title: String, notes: String?) throws {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        r.title = title
        r.notes = (notes?.isEmpty == true) ? nil : notes
        try store.save(r, commit: true)
    }

    func delete(id: String) throws {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        try store.remove(r, commit: true)
    }
}
