# Tasks: status-bar-clickthrough

- [x] `StatusBarView.hitTest(_:)` returns nil (display-only → click-through), so it can't block the
      Tools-pane toggle or window dragging in the title-bar strip.
- [x] Build clean; suite green (121); live-gated (toggle works with the status bar enabled).
