import AppKit

/// A borderless icon button that shows a hover highlight (rounded background + brighter tint),
/// signalling it's clickable.
@MainActor
final class HoverIconButton: NSButton {
    /// Tint when not hovered (hover brightens to `.labelColor`).
    var restingTint: NSColor = .secondaryLabelColor { didSet { if !hovering { contentTintColor = restingTint } } }
    private var hovering = false
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(t); tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        contentTintColor = .labelColor
        NSCursor.pointingHand.set()
    }
    override func mouseExited(with event: NSEvent) {
        hovering = false
        layer?.backgroundColor = .clear
        contentTintColor = restingTint
        NSCursor.arrow.set()
    }
}
