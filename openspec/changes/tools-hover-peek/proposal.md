# Proposal: tools-hover-peek

Make the right **Tools** pane behave like the left sidebar: **hover-peek** it open, and move its toggle
**onto the pane**.

## What changed

Previously the Tools pane only opened/closed via a button floating at the window's top-right corner, and
it hid via `isHidden`. Now it mirrors the left sidebar exactly:
- **Hover the right edge** (when collapsed) → the pane slides in from the right as a **floating, rounded,
  shadowed overlay** over the web card. Moving off it slides it back.
- **The toggle moved inside the pane** (top-right, `sidebar.right`) — like the left toggle lives in its
  sidebar. Click to pin open / collapse. ⌘⌥T + the palette command still work; opening a tool still pins it.

## How

Same machinery as the left peek:
- A sliding `toolsTrailingConstraint` (off-screen `+toolsWidth` when collapsed, `0` when shown) replaces
  the fixed trailing + `isHidden`.
- A `toolsPeeking` state; right-edge detection (`x ≥ width−4`) added to the mouse monitor; `ToolsSidebar`
  gains `onEntered`/`onExited` (a tracking area, mirroring `HoverView`) → `openToolsPeek`/`closeToolsPeek`.
- `setToolsFloating` toggles the pane's shadow + corner radius; the resize splitter is suppressed while
  floating. Pinned state persists as before.

## Impact

`AppShell` (peek machinery, sliding constraint, mouse-edge detection, toggle reparented into the pane),
`ToolsSidebar` (hover reporting). 116 XCTests green; live-gated.
