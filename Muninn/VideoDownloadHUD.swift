import AppKit

/// A small progress row for an in-flight video download — title, status/percent, a determinate bar,
/// and a cancel ×. The shell stacks these top-right and removes them on completion.
@MainActor
final class VideoDownloadHUD: NSView {
    var onCancel: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "Starting…")
    private let bar = NSProgressIndicator()

    init(title: String, tint: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = tint.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        let fg = AppShell.contrastingText(tint)
        layer?.borderColor = fg.withAlphaComponent(0.12).cgColor
        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22; layer?.shadowRadius = 12; layer?.shadowOffset = CGSize(width: 0, height: -3)
        translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)) ?? NSImage())
        icon.contentTintColor = fg
        icon.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = fg
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = fg.withAlphaComponent(0.8)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        bar.style = .bar
        bar.isIndeterminate = true
        bar.minValue = 0; bar.maxValue = 1
        bar.controlSize = .small
        bar.startAnimation(nil)
        bar.translatesAutoresizingMaskIntoConstraints = false

        let cancel = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Cancel") ?? NSImage(),
                              target: self, action: #selector(cancelTapped))
        cancel.isBordered = false; cancel.contentTintColor = fg
        cancel.translatesAutoresizingMaskIntoConstraints = false

        let text = NSStackView(views: [titleLabel, statusLabel])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 1
        text.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon); addSubview(text); addSubview(bar); addSubview(cancel)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 260),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            text.trailingAnchor.constraint(equalTo: cancel.leadingAnchor, constant: -8),
            cancel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            cancel.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            bar.leadingAnchor.constraint(equalTo: text.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: cancel.leadingAnchor, constant: -8),
            bar.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 6),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(fraction: Double, status: String) {
        statusLabel.stringValue = status
        if fraction > 0 {
            if bar.isIndeterminate { bar.isIndeterminate = false; bar.stopAnimation(nil) }
            bar.doubleValue = min(max(fraction, 0), 1)
        }
    }

    @objc private func cancelTapped() { onCancel?() }
}
