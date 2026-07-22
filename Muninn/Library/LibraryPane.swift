import AppKit

/// The Library: a left-side overlay pane (slides in over everything), workspace-tinted with
/// rounded corners. Hosts **Downloads** (list) and **Media** (image/video/audio grid).
@MainActor
final class LibraryPane: NSView {
    var onClose: (() -> Void)?

    private let store: DownloadStore
    private let tint: NSColor
    private let shadowHost = NSView()
    private let card = NSView()
    private let segmented = NSSegmentedControl(labels: ["Downloads", "Media"], trackingMode: .selectOne, target: nil, action: nil)
    private let content = NSView()
    private var panelLeading: NSLayoutConstraint!
    private static let panelWidth: CGFloat = 360

    init(store: DownloadStore, tint: NSColor) {
        self.store = store
        self.tint = tint
        super.init(frame: .zero)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    // Click outside the pane closes it.
    override func mouseDown(with event: NSEvent) {
        if !shadowHost.frame.contains(convert(event.locationInWindow, from: nil)) { close() }
    }

    private func build() {
        shadowHost.wantsLayer = true
        shadowHost.shadow = NSShadow()
        shadowHost.layer?.shadowColor = NSColor.black.cgColor
        shadowHost.layer?.shadowOpacity = 0.28
        shadowHost.layer?.shadowRadius = 22
        shadowHost.layer?.shadowOffset = CGSize(width: 3, height: 0)
        shadowHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shadowHost)

        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = tint.cgColor       // match the current space
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        shadowHost.addSubview(card)

        let title = NSTextField(labelWithString: "Library")
        title.font = .systemFont(ofSize: 13, weight: .semibold); title.textColor = .labelColor
        title.translatesAutoresizingMaskIntoConstraints = false
        let closeBtn = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!, target: self, action: #selector(closeClicked))
        closeBtn.isBordered = false; closeBtn.contentTintColor = .secondaryLabelColor
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        segmented.selectedSegment = 0
        segmented.target = self; segmented.action = #selector(segmentChanged)
        segmented.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false

        for s in [title, closeBtn, segmented, content] { card.addSubview(s) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            closeBtn.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            closeBtn.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            segmented.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            segmented.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            segmented.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 16),
            content.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            card.topAnchor.constraint(equalTo: shadowHost.topAnchor),
            card.leadingAnchor.constraint(equalTo: shadowHost.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: shadowHost.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: shadowHost.bottomAnchor),
        ])
    }

    /// Add to `parent`, filling it, and slide the pane in from the left.
    func present(in parent: NSView) {
        frame = parent.bounds
        autoresizingMask = [.width, .height]
        parent.addSubview(self)
        panelLeading = shadowHost.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -(Self.panelWidth + 40))
        NSLayoutConstraint.activate([
            panelLeading,
            shadowHost.topAnchor.constraint(equalTo: topAnchor, constant: 34),   // clear the title-bar strip
            shadowHost.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            shadowHost.widthAnchor.constraint(equalToConstant: Self.panelWidth),
        ])
        select(0)
        layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            panelLeading.constant = 10
            layoutSubtreeIfNeeded()
        }
    }

    func close() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            panelLeading.constant = -(Self.panelWidth + 40)
            layoutSubtreeIfNeeded()
        }, completionHandler: { [weak self] in
            self?.removeFromSuperview(); self?.onClose?()
        })
    }
    @objc private func closeClicked() { close() }
    @objc private func segmentChanged() { select(segmented.selectedSegment) }

    private func select(_ index: Int) {
        segmented.selectedSegment = index
        content.subviews.forEach { $0.removeFromSuperview() }
        let view = index == 0 ? downloadsView() : mediaView()
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    // MARK: Downloads (list)

    private func downloadsView() -> NSView {
        let records = store.records
        if records.isEmpty { return emptyState("No downloads yet.") }
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        for r in records { stack.addArrangedSubview(downloadRow(r)) }
        return scrollWrap(stack) { inner, doc in inner.widthAnchor.constraint(equalTo: doc.widthAnchor, constant: -32).isActive = true }
    }

    private func downloadRow(_ r: DownloadRecord) -> NSView {
        let row = HoverRow()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: r.path))
        icon.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: r.filename)
        name.font = .systemFont(ofSize: 13, weight: .medium); name.lineBreakMode = .byTruncatingMiddle
        let detail = NSTextField(labelWithString: subtitle(r))
        detail.font = .systemFont(ofSize: 11); detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingTail
        let labels = NSStackView(views: [name, detail]); labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 1

        let reveal = NSButton(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Reveal in Finder")!, target: self, action: #selector(revealClicked(_:)))
        let remove = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove")!, target: self, action: #selector(removeClicked(_:)))
        for b in [reveal, remove] { b.isBordered = false; b.contentTintColor = .secondaryLabelColor; b.identifier = NSUserInterfaceItemIdentifier(r.id.uuidString) }
        let actions = NSStackView(views: [reveal, remove]); actions.orientation = .horizontal; actions.spacing = 2

        row.onDoubleClick = { [weak self] in self?.open(r) }
        row.menu = downloadMenu(for: r)   // right-click: Open / Show in Finder / Copy Path / Trash / Remove
        for s in [icon, labels, actions] { s.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(s) }
        if !r.exists { name.textColor = .tertiaryLabelColor }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28), icon.heightAnchor.constraint(equalToConstant: 28),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            labels.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            actions.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            actions.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -10),
        ])
        return row
    }

    // MARK: Media (grid)

    private func mediaView() -> NSView {
        let media = store.records.filter { $0.isMedia }
        if media.isEmpty { return emptyState("No media downloads yet.") }
        let grid = NSStackView()
        grid.orientation = .vertical; grid.alignment = .leading; grid.spacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        var rowStack: NSStackView?
        for (i, r) in media.enumerated() {
            if i % 2 == 0 {
                let rs = NSStackView(); rs.orientation = .horizontal; rs.spacing = 12; rs.alignment = .top
                grid.addArrangedSubview(rs); rowStack = rs
            }
            rowStack?.addArrangedSubview(mediaTile(r))
        }
        return scrollWrap(grid) { _, _ in }
    }

    private func mediaTile(_ r: DownloadRecord) -> NSView {
        let tile = HoverRow()
        tile.onDoubleClick = { [weak self] in self?.open(r) }
        tile.menu = downloadMenu(for: r)
        tile.translatesAutoresizingMaskIntoConstraints = false
        let thumb = NSImageView()
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true; thumb.layer?.cornerRadius = 6; thumb.layer?.masksToBounds = true
        thumb.image = r.isImage ? (NSImage(contentsOfFile: r.path) ?? NSWorkspace.shared.icon(forFile: r.path))
                                : NSWorkspace.shared.icon(forFile: r.path)
        thumb.translatesAutoresizingMaskIntoConstraints = false
        let caption = NSTextField(labelWithString: r.filename)
        caption.font = .systemFont(ofSize: 11); caption.textColor = .secondaryLabelColor
        caption.lineBreakMode = .byTruncatingMiddle; caption.alignment = .center
        caption.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(thumb); tile.addSubview(caption)
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 150),
            thumb.topAnchor.constraint(equalTo: tile.topAnchor),
            thumb.leadingAnchor.constraint(equalTo: tile.leadingAnchor),
            thumb.trailingAnchor.constraint(equalTo: tile.trailingAnchor),
            thumb.heightAnchor.constraint(equalToConstant: 110),
            caption.topAnchor.constraint(equalTo: thumb.bottomAnchor, constant: 5),
            caption.leadingAnchor.constraint(equalTo: tile.leadingAnchor),
            caption.trailingAnchor.constraint(equalTo: tile.trailingAnchor),
            caption.bottomAnchor.constraint(equalTo: tile.bottomAnchor),
        ])
        return tile
    }

    // MARK: shared

    private func subtitle(_ r: DownloadRecord) -> String {
        let size = ByteCountFormatter.string(fromByteCount: r.byteSize, countStyle: .file)
        let host = r.sourceURL.flatMap { URL(string: $0)?.host } ?? ""
        let when = Self.dateFormatter.string(from: r.date)
        return [host, size, when].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func emptyState(_ text: String) -> NSView {
        let v = NSView()
        let l = NSTextField(labelWithString: text); l.font = .systemFont(ofSize: 13); l.textColor = .tertiaryLabelColor
        l.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(l)
        NSLayoutConstraint.activate([l.centerXAnchor.constraint(equalTo: v.centerXAnchor), l.centerYAnchor.constraint(equalTo: v.centerYAnchor, constant: -30)])
        return v
    }

    private func scrollWrap(_ inner: NSView, _ pin: (NSView, NSView) -> Void) -> NSView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = NSView(); doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(inner); scroll.documentView = doc
        NSLayoutConstraint.activate([
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            inner.topAnchor.constraint(equalTo: doc.topAnchor, constant: 8),
            inner.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 16),
            inner.trailingAnchor.constraint(lessThanOrEqualTo: doc.trailingAnchor, constant: -16),
            inner.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -12),
        ])
        pin(inner, doc)
        return scroll
    }

    private func recordFor(_ sender: NSView) -> DownloadRecord? {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return nil }
        return store.records.first { $0.id == id }
    }
    private func open(_ r: DownloadRecord) { if r.exists { NSWorkspace.shared.open(r.url) } else { NSSound.beep() } }
    @objc private func revealClicked(_ s: NSButton) { if let r = recordFor(s), r.exists { NSWorkspace.shared.activateFileViewerSelecting([r.url]) } }
    @objc private func removeClicked(_ s: NSButton) { if let r = recordFor(s) { store.remove(r.id); select(segmented.selectedSegment) } }

    // MARK: right-click menu (Finder-style)

    private func downloadMenu(for r: DownloadRecord) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false   // respect our per-item enabled state
        func item(_ title: String, _ action: Selector, enabled: Bool = true) -> NSMenuItem {
            let m = NSMenuItem(title: title, action: action, keyEquivalent: "")
            m.target = self; m.representedObject = r.id.uuidString; m.isEnabled = enabled
            return m
        }
        menu.addItem(item("Open", #selector(menuOpen(_:)), enabled: r.exists))
        menu.addItem(item("Show in Finder", #selector(menuReveal(_:)), enabled: r.exists))
        menu.addItem(item("Copy Path", #selector(menuCopyPath(_:)), enabled: r.exists))
        menu.addItem(.separator())
        menu.addItem(item("Move to Trash", #selector(menuTrash(_:)), enabled: r.exists))
        menu.addItem(item("Remove from List", #selector(menuRemoveFromList(_:))))
        return menu
    }

    private func record(from s: NSMenuItem) -> DownloadRecord? {
        guard let raw = s.representedObject as? String, let id = UUID(uuidString: raw) else { return nil }
        return store.records.first { $0.id == id }
    }
    @objc private func menuOpen(_ s: NSMenuItem) { if let r = record(from: s) { open(r) } }
    @objc private func menuReveal(_ s: NSMenuItem) { if let r = record(from: s), r.exists { NSWorkspace.shared.activateFileViewerSelecting([r.url]) } }
    @objc private func menuCopyPath(_ s: NSMenuItem) {
        guard let r = record(from: s) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(r.url.path, forType: .string)
    }
    @objc private func menuTrash(_ s: NSMenuItem) {
        guard let r = record(from: s) else { return }
        NSWorkspace.shared.recycle([r.url]) { [weak self] _, _ in     // recoverable (Trash), not a hard delete
            DispatchQueue.main.async { self?.store.remove(r.id); self?.select(self?.segmented.selectedSegment ?? 0) }
        }
    }
    @objc private func menuRemoveFromList(_ s: NSMenuItem) { if let r = record(from: s) { store.remove(r.id); select(segmented.selectedSegment) } }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()
}

/// A row/tile that reports double-clicks and shows a hover highlight.
final class HoverRow: NSView {
    var onDoubleClick: (() -> Void)?
    private var tracking: NSTrackingArea?
    override func mouseDown(with event: NSEvent) { if event.clickCount == 2 { onDoubleClick?() } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(t); tracking = t
    }
    override func mouseEntered(with event: NSEvent) {
        wantsLayer = true; layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor; layer?.cornerRadius = 6
    }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = .clear }
}
