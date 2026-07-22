import AppKit

/// The Notifications tool (Tools sidebar): a history of the toasts Muninn has shown, so a missed
/// one can be reviewed. Cleared automatically past the retention window, or manually here.
@MainActor
final class NotificationsView: NSView {
    var onClear: (() -> Void)?

    private let list = NSStackView()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No notifications.")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let clear = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear")!,
                             target: self, action: #selector(clearTapped))
        clear.isBordered = false; clear.contentTintColor = .secondaryLabelColor
        clear.toolTip = "Clear notifications"
        clear.translatesAutoresizingMaskIntoConstraints = false
        let bar = NSStackView(views: [NSView(), clear])   // spacer pushes clear to the right
        bar.orientation = .horizontal
        bar.translatesAutoresizingMaskIntoConstraints = false

        list.orientation = .vertical; list.alignment = .leading; list.spacing = 8
        list.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedContainer(); doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(list)
        scroll.documentView = doc; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 12); emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center; emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(bar); addSubview(scroll); addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            list.topAnchor.constraint(equalTo: doc.topAnchor, constant: 4),
            list.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 2),
            list.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -2),
            list.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -4),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    @objc private func clearTapped() { onClear?() }

    func reload(_ items: [AppNotification]) {
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        emptyLabel.isHidden = !items.isEmpty
        scroll.isHidden = items.isEmpty
        let fmt = RelativeDateTimeFormatter(); fmt.unitsStyle = .abbreviated
        for n in items {
            let row = row(text: n.text, when: fmt.localizedString(for: n.date, relativeTo: Date()))
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
    }

    private func row(text: String, when: String) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 8
        card.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        let msg = NSTextField(wrappingLabelWithString: text)
        msg.font = .systemFont(ofSize: 12); msg.textColor = .labelColor
        msg.translatesAutoresizingMaskIntoConstraints = false
        let time = NSTextField(labelWithString: when)
        time.font = .systemFont(ofSize: 10); time.textColor = .tertiaryLabelColor
        time.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(msg); card.addSubview(time)
        NSLayoutConstraint.activate([
            msg.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            msg.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            msg.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            time.topAnchor.constraint(equalTo: msg.bottomAnchor, constant: 3),
            time.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            time.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
        ])
        return card
    }
}

/// Top-left-origin container so the list grows downward in the scroll view.
private final class FlippedContainer: NSView { override var isFlipped: Bool { true } }
