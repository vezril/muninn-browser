import AppKit

/// Arc-style command bar: a floating overlay to search the web (DuckDuckGo default),
/// open a URL, switch to an open tab, or jump to a history entry. Opened with Cmd+N.
@MainActor
final class CommandPalette: NSView {
    /// A single actionable row.
    struct Item {
        enum Kind { case tab(Int), url(URL), search(String) }
        let kind: Kind
        let title: String
        let detail: String?
        let trailing: String?
        let symbol: String
    }

    var onExecute: ((Item) -> Void)?
    var onClose: (() -> Void)?

    /// Data the host refreshes each time the palette opens.
    var openTabs: [(id: Int, title: String, url: URL?)] = []
    var history: [HistoryEntry] = []
    var searchEngineName = "DuckDuckGo"

    private let panel = NSView()
    private let field = NSTextField()
    private let listStack = NSStackView()
    private var items: [Item] = []
    private var selected = 0

    override var acceptsFirstResponder: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        buildPanel()
    }
    required init?(coder: NSCoder) { fatalError() }

    // Click on the scrim (outside the panel) closes.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if !panel.frame.contains(p) { onClose?() }
    }

    private func buildPanel() {
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 12
        panel.layer?.backgroundColor = NSColor(white: 0.14, alpha: 0.98).cgColor
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        panel.layer?.masksToBounds = true
        panel.shadow = NSShadow()
        panel.layer?.shadowColor = NSColor.black.cgColor
        panel.layer?.shadowOpacity = 0.4
        panel.layer?.shadowRadius = 30
        panel.layer?.shadowOffset = CGSize(width: 0, height: -10)
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)

        let glass = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))!)
        glass.contentTintColor = .secondaryLabelColor
        glass.translatesAutoresizingMaskIntoConstraints = false

        field.placeholderString = "Search or Enter URL…"
        field.font = .systemFont(ofSize: 18, weight: .regular)
        field.textColor = .labelColor
        field.focusRingType = .none
        field.isBordered = false
        field.drawsBackground = false
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(glass); header.addSubview(field)

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 2
        listStack.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(header)
        panel.addSubview(listStack)
        NSLayoutConstraint.activate([
            panel.widthAnchor.constraint(equalToConstant: 660),
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor, constant: 120),

            header.topAnchor.constraint(equalTo: panel.topAnchor),
            header.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 58),
            glass.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            glass.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: glass.trailingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            field.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            listStack.topAnchor.constraint(equalTo: header.bottomAnchor),
            listStack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            listStack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            listStack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8),
        ])
    }

    /// Focus the field and show initial suggestions when shown.
    func activate(in parent: NSView) {
        frame = parent.bounds
        autoresizingMask = [.width, .height]
        parent.addSubview(self)
        rebuild()
        window?.makeFirstResponder(field)
    }

    // MARK: results

    private static func asURL(_ q: String) -> URL? {
        let s = q.trimmingCharacters(in: .whitespaces)
        guard !s.contains(" ") else { return nil }
        if s.contains("://"), let u = URL(string: s) { return u }
        // host-like: has a dot and a tld-ish tail, or localhost
        guard s.contains("."), let u = URL(string: "https://" + s), u.host != nil else { return nil }
        return u
    }

    private func rebuild() {
        let q = field.stringValue.trimmingCharacters(in: .whitespaces)
        var out: [Item] = []
        if !q.isEmpty {
            if let url = Self.asURL(q) {
                out.append(Item(kind: .url(url), title: url.absoluteString, detail: "Open", trailing: nil, symbol: "globe"))
            } else {
                out.append(Item(kind: .search(q), title: "Search \(searchEngineName) for “\(q)”", detail: nil, trailing: nil, symbol: "magnifyingglass"))
            }
        }
        let ql = q.lowercased()
        func match(_ text: String...) -> Bool { q.isEmpty || text.contains { $0.lowercased().contains(ql) } }
        for t in openTabs where match(t.title, t.url?.absoluteString ?? "") {
            out.append(Item(kind: .tab(t.id), title: t.title.isEmpty ? (t.url?.host ?? "Tab") : t.title,
                            detail: t.url?.host, trailing: "Switch to Tab", symbol: "square.on.square"))
        }
        for h in history where match(h.title, h.url) {
            if let u = URL(string: h.url) {
                out.append(Item(kind: .url(u), title: h.title, detail: URL(string: h.url)?.host, trailing: nil, symbol: "clock"))
            }
        }
        items = Array(out.prefix(8))
        selected = min(selected, max(items.count - 1, 0))
        renderRows()
    }

    private func renderRows() {
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, item) in items.enumerated() {
            listStack.addArrangedSubview(makeRow(item, index: i, selected: i == selected))
        }
        listStack.isHidden = items.isEmpty
    }

    private func makeRow(_ item: Item, index: Int, selected: Bool) -> NSView {
        let row = PaletteRow()
        row.onClick = { [weak self] in self?.selected = index; self?.execute() }
        row.onHover = { [weak self] in self?.moveSelection(to: index) }
        row.wantsLayer = true
        row.layer?.cornerRadius = 8
        row.layer?.backgroundColor = selected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 44).isActive = true
        row.widthAnchor.constraint(equalToConstant: 660 - 16).isActive = true

        let fg: NSColor = selected ? .white : .labelColor
        let sub: NSColor = selected ? NSColor(white: 1, alpha: 0.8) : .secondaryLabelColor

        let icon = NSImageView(image: NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))!)
        icon.contentTintColor = fg
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: item.title)
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.textColor = fg
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false

        let trailing = NSTextField(labelWithString: item.trailing ?? item.detail ?? "")
        trailing.font = .systemFont(ofSize: 12)
        trailing.textColor = sub
        trailing.lineBreakMode = .byTruncatingTail
        trailing.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        trailing.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(icon); row.addSubview(title); row.addSubview(trailing)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            trailing.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 10),
            trailing.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            trailing.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func moveSelection(to i: Int) {
        guard items.indices.contains(i), i != selected else { return }
        selected = i; renderRows()
    }
    private func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + delta + items.count) % items.count
        renderRows()
    }
    private func execute() {
        if items.indices.contains(selected) { onExecute?(items[selected]) }
        else {
            let q = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty { onExecute?(Item(kind: .search(q), title: q, detail: nil, trailing: nil, symbol: "magnifyingglass")) }
        }
    }
}

extension CommandPalette: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) { rebuild() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):      moveSelection(by: 1); return true
        case #selector(NSResponder.moveUp(_:)):        moveSelection(by: -1); return true
        case #selector(NSResponder.insertNewline(_:)): execute(); return true
        case #selector(NSResponder.cancelOperation(_:)): onClose?(); return true
        default: return false
        }
    }
}

/// A palette result row: click to run, hover to select.
final class PaletteRow: NSView {
    var onClick: (() -> Void)?
    var onHover: (() -> Void)?
    private var area: NSTrackingArea?
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = area { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a); area = a
    }
    override func mouseEntered(with event: NSEvent) { onHover?() }
}
