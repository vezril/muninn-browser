# Proposal: shortcuts-command-bar

## Why

Daily-driver keyboard ergonomics: fast navigation, tab management, and copy/share
without reaching for the mouse — plus an Arc-style command bar to search / open / switch.

## What Changes

- **Command palette (Cmd+N)** — a floating overlay (current window) to search the web
  (DuckDuckGo default), open a URL, switch to an open tab, or jump to a history entry.
  Backed by a persisted `HistoryStore` (recorded on navigation). ↑/↓ navigate, Enter runs,
  Esc / click-outside closes.
- **Shortcuts:**
  - Cmd+W — close current tab; **pinned/favourite tabs unload (free memory) but stay** in
    the sidebar (lazy-reload on select); regular tabs are removed (and remembered).
  - Cmd+D — pin/unpin the current tab.
  - Cmd+Shift+T — reopen the last closed tab.
  - Cmd+Shift+C — copy current tab URL (with a toast).
  - Cmd+Shift+Option+C — copy current tab URL as Markdown.
  - Cmd+Shift+K — clear unpinned tabs in the active workspace.
  - Standard editing (Cmd A/C/V/X/Z) via a proper **Edit menu**.
- **Copy toast** — a top-right, workspace-tinted toast with a filled-accent **Share** button
  (standard macOS share sheet: AirDrop, Mail, Messages, …). Stays while hovered / while the
  share sheet is open; haptic + press-flash feedback on Share; slide-in/out animation.

## Scope / cutline

Cmd+N opens the palette in the **current window** (chosen over full multi-window, which would
require a shared shim host + sidebar store). True new windows deferred.

## Impact

`AppShell` (shortcuts, palette host, toast, unload/close semantics, history recording);
new `CommandPalette` + `HistoryStore`; `AppDelegate` gains an Edit menu; `BrowserTab.unload()`;
`HoverView` gains `onEntered`.
