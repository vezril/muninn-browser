# Tasks: tools-hover-peek

- [x] Sliding `toolsTrailingConstraint` (collapsed = +toolsWidth off-screen, shown = 0); drop `isHidden`.
- [x] `toolsPeeking` state; right-edge detection in the mouse monitor; `setToolsFloating` (shadow+radius).
- [x] `openToolsPeek`/`closeToolsPeek`/`slideTools`; `setToolsOpen` rewritten to the slide model.
- [x] `ToolsSidebar` gains `onEntered`/`onExited` (tracking area) → close-on-exit.
- [x] Toggle button reparented into the pane (top-right); removed the window-corner button.
- [x] Build clean; full suite green (116); live-gated (peek/pin/collapse cycle).
