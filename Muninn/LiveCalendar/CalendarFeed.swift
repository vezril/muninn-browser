import Foundation

/// Fetches the configured Live Calendars' ICS share links natively (no credentials — an
/// unauthenticated GET of a user-pasted public URL), parses them locally, and keeps the
/// combined event set. Polls on an interval and can be refreshed on demand; the last good
/// parse per calendar is retained across transient failures.
@MainActor
final class CalendarFeed {
    /// Combined events across all calendars (each stamped with its `calendarId`).
    private(set) var events: [VEvent] = []
    /// Called on the main actor after any refresh that changes the event set.
    var onUpdate: (() -> Void)?

    private var calendars: [LiveCalendar] = []
    private var cache: [UUID: [VEvent]] = [:]   // last good parse per calendar
    private var timer: Timer?
    private let session: URLSession
    private var inFlight = false

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 20
        session = URLSession(configuration: cfg)
    }

    func start(interval: TimeInterval = 300) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Replace the configured calendars; drops cache for removed ones and refetches.
    func setCalendars(_ c: [LiveCalendar]) {
        calendars = c
        let ids = Set(c.map { $0.id })
        cache = cache.filter { ids.contains($0.key) }
        rebuildEvents()
        refresh()
    }

    /// The soonest not-yet-ended occurrence across all calendars.
    func nextOccurrence(now: Date = Date()) -> Occurrence? {
        Recurrence.nextOccurrence(in: events, now: now)
    }

    /// Fetch every calendar; update its cache only on success (last-good otherwise).
    func refresh() {
        guard !inFlight, !calendars.isEmpty else { return }
        inFlight = true
        let toFetch = calendars
        Task { @MainActor in
            var changed = false
            for cal in toFetch {
                guard let url = Self.normalize(cal.icsURL) else { continue }
                do {
                    let (data, resp) = try await session.data(from: url)
                    guard (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                          let text = String(data: data, encoding: .utf8) else { continue }
                    var parsed = ICSParser.parse(text)
                    for i in parsed.indices { parsed[i].calendarId = cal.id }
                    cache[cal.id] = parsed
                    changed = true
                } catch {
                    // keep last-good; retried next poll
                }
            }
            inFlight = false
            if changed { rebuildEvents(); onUpdate?() }
        }
    }

    private func rebuildEvents() {
        events = calendars.flatMap { cache[$0.id] ?? [] }
    }

    /// `webcal://` → `https://`; require http(s).
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("webcal://") { s = "https://" + s.dropFirst("webcal://".count) }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return url
    }
}
