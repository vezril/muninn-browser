# Proposal: status-bar-clickthrough

Fix: with the weather status bar enabled, the **Tools-pane toggle stopped working**.

## Cause & fix

`StatusBarView` had no width constraint (only `centerX` + loose `leading≥`/`trailing≤`), so it stretched
nearly full-width across the title-bar strip, and it sits *above* the Tools pane in z-order. A plain
`NSView` hit-tests across its whole bounds — including transparent areas — so when the Tools pane peeks
in, the invisible bar covered the toggle and ate its clicks.

The status bar is display-only, so it now returns `nil` from `hitTest(_:)` — fully click-through. This
also stops it blocking window-dragging in that strip. Only manifested when the status bar was enabled.

## Impact

One override in `StatusBarView`. 121 XCTests green; live-gated.
