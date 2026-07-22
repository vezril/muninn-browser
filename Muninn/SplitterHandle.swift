import AppKit

/// A thin, transparent vertical strip that sits on a pane's inner edge and reports horizontal
/// drag deltas so the pane can be resized. Shows the left-right resize cursor on hover.
@MainActor
final class SplitterHandle: NSView {
    /// Called continuously with the horizontal delta (window-space) while dragging.
    var onDrag: ((CGFloat) -> Void)?
    /// Called once when the drag ends (commit: rebuild dependent layout + persist).
    var onDragEnd: (() -> Void)?

    private var tracking: NSTrackingArea?
    private var lastX: CGFloat = 0

    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .cursorUpdate, .activeInActiveApp, .inVisibleRect],
                               owner: self)
        addTrackingArea(t); tracking = t
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseDown(with event: NSEvent) { lastX = event.locationInWindow.x }
    override func mouseDragged(with event: NSEvent) {
        let x = event.locationInWindow.x
        onDrag?(x - lastX)
        lastX = x
    }
    override func mouseUp(with event: NSEvent) { onDragEnd?() }
}
