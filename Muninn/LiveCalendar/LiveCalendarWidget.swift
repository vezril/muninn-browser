import AppKit

/// The Live Calendar tool: shows the next event, a live countdown, and a Join button that
/// appears within the calendar's lead time when the event carries a video-call link.
@MainActor
final class LiveCalendarWidget: NSView {
    var onJoin: ((URL) -> Void)?

    private let caption = NSTextField(labelWithString: "UP NEXT")
    private let titleLabel = NSTextField(labelWithString: "")
    private let whenLabel = NSTextField(labelWithString: "")
    private let joinButton = NSButton(title: "Join", target: nil, action: nil)

    private var joinURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        caption.font = .systemFont(ofSize: 10, weight: .bold)
        caption.textColor = .tertiaryLabelColor

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.cell?.wraps = true

        whenLabel.font = .systemFont(ofSize: 12)
        whenLabel.textColor = .secondaryLabelColor
        whenLabel.lineBreakMode = .byTruncatingTail

        joinButton.bezelStyle = .rounded
        joinButton.wantsLayer = true
        joinButton.isBordered = false
        joinButton.layer?.cornerRadius = 7
        joinButton.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        joinButton.contentTintColor = .white
        joinButton.attributedTitle = NSAttributedString(string: "Join", attributes: [
            .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        joinButton.target = self
        joinButton.action = #selector(joinTapped)
        joinButton.isHidden = true

        let stack = NSStackView(views: [caption, titleLabel, whenLabel, joinButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(10, after: whenLabel)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            joinButton.heightAnchor.constraint(equalToConstant: 30),
            joinButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
        ])
    }

    /// Refresh from the resolved next occurrence (nil → no upcoming events).
    func update(occurrence: Occurrence?, leadTimeMinutes: Int, now: Date = Date()) {
        guard let occ = occurrence else {
            titleLabel.stringValue = "No upcoming events"
            whenLabel.stringValue = ""
            joinButton.isHidden = true
            joinURL = nil
            return
        }
        titleLabel.stringValue = occ.title.isEmpty ? "(untitled event)" : occ.title
        whenLabel.stringValue = Self.whenText(occ: occ, now: now)

        joinURL = occ.joinURL
        let withinLead = occ.start.timeIntervalSince(now) <= Double(leadTimeMinutes) * 60
        joinButton.isHidden = !(withinLead && joinURL != nil)
    }

    @objc private func joinTapped() { if let u = joinURL { onJoin?(u) } }

    // MARK: formatting

    /// "9:00 AM · in 4 min" (or "· now" while it's happening).
    static func whenText(occ: Occurrence, now: Date) -> String {
        let time = timeFormatter.string(from: occ.start)
        let day = dayPrefix(occ.start, now: now)
        return "\(day)\(time) · \(countdown(from: now, to: occ.start, end: occ.end))"
    }

    static func countdown(from now: Date, to start: Date, end: Date) -> String {
        if now >= start { return now < end ? "now" : "ended" }
        let secs = Int(start.timeIntervalSince(now))
        if secs < 60 { return "in <1 min" }
        let mins = secs / 60
        if mins < 60 { return "in \(mins) min" }
        let hours = mins / 60, rem = mins % 60
        if hours < 24 { return rem == 0 ? "in \(hours)h" : "in \(hours)h \(rem)m" }
        let days = hours / 24
        return "in \(days) day\(days == 1 ? "" : "s")"
    }

    /// "" for today, "Tomorrow, " / weekday prefix otherwise.
    private static func dayPrefix(_ date: Date, now: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return "" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow, "
        }
        return weekdayFormatter.string(from: date) + ", "
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
}
