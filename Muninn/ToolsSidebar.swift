import AppKit

/// The right-hand Tools sidebar: a workspace-tinted panel that hosts a vertical stack of
/// tool widgets (the Live Calendar is the first). Mirrors the left sidebar's visual language
/// — flush to the window edge, tinted, framing the floating web card on the right.
///
/// Group 1 (this change) ships the shell + an empty state; tools are added into `contentStack`.
@MainActor
final class ToolsSidebar: NSView {
    /// Where tool widgets are stacked (top → bottom). Add/remove arranged subviews, then
    /// call `refreshEmptyState()`.
    let contentStack = NSStackView()

    private let header = NSTextField(labelWithString: "Tools")
    private let emptyLabel = NSTextField(labelWithString: "No tools yet.\nAdd a calendar in Settings → Calendars.")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.maximumNumberOfLines = 3
        emptyLabel.lineBreakMode = .byWordWrapping
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(header); addSubview(contentStack); addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 44),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            contentStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
        refreshEmptyState()
    }

    /// Show the empty-state message only while no tools are stacked.
    func refreshEmptyState() {
        let hasTools = !contentStack.arrangedSubviews.isEmpty
        emptyLabel.isHidden = hasTools
        contentStack.isHidden = !hasTools
    }

    /// Match the active workspace tint (called from `applyWorkspaceTint`).
    func applyTint(_ color: NSColor) {
        layer?.backgroundColor = color.cgColor
    }
}
