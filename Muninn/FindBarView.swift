import AppKit

/// In-page find bar (⌘F): a floating search field with prev/next and a match count, driving WKWebView's
/// native `findString` highlighting. Anchored top-right over the web card. Enter = next, ⇧-click prev,
/// Esc = close.
@MainActor
final class FindBarView: NSView {
    var onQueryChange: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrev: (() -> Void)?
    var onClose: (() -> Void)?

    let field = NSTextField()
    private let countLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 9
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.20
        layer?.shadowRadius = 9
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        // A borderless field inside the rounded card — the card *is* the search box (no nested bezels).
        let mag = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)) ?? NSImage())
        mag.contentTintColor = .secondaryLabelColor
        mag.translatesAutoresizingMaskIntoConstraints = false
        mag.setContentHuggingPriority(.required, for: .horizontal)

        field.placeholderString = "Find on page"
        field.delegate = self
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 190).isActive = true

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 62).isActive = true

        func iconButton(_ symbol: String, _ action: Selector, _ tip: String) -> NSButton {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(),
                             target: self, action: action)
            b.isBordered = false; b.bezelStyle = .regularSquare
            b.contentTintColor = .secondaryLabelColor
            b.toolTip = tip
            return b
        }
        let prev = iconButton("chevron.up", #selector(prevTapped), "Previous (⇧⌘G)")
        let next = iconButton("chevron.down", #selector(nextTapped), "Next (⌘G)")
        let close = iconButton("xmark", #selector(closeTapped), "Done (Esc)")

        let stack = NSStackView(views: [mag, field, countLabel, prev, next, close])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.setCustomSpacing(6, after: mag)
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @objc private func prevTapped() { onPrev?() }
    @objc private func nextTapped() { onNext?() }
    @objc private func closeTapped() { onClose?() }

    /// Update the count/status readout. `count == nil` → don't show a number (just found/not-found).
    func setState(found: Bool, count: Int?) {
        if field.stringValue.isEmpty { countLabel.stringValue = ""; countLabel.textColor = .secondaryLabelColor; return }
        if !found { countLabel.stringValue = "No results"; countLabel.textColor = .systemRed; return }
        countLabel.textColor = .secondaryLabelColor
        if let count, count > 0 { countLabel.stringValue = "\(count) match\(count == 1 ? "" : "es")" }
        else { countLabel.stringValue = "" }
    }

    func focus() { window?.makeFirstResponder(field); field.selectText(nil) }
}

extension FindBarView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) { onQueryChange?(field.stringValue) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)): onNext?(); return true
        case #selector(NSResponder.cancelOperation(_:)): onClose?(); return true
        default: return false
        }
    }
}
