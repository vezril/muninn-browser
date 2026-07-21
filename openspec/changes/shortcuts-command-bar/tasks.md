# Tasks: shortcuts-command-bar

## 1. Shortcuts

- [x] 1.1 Key monitor handles Cmd+N/W/D, Cmd+Shift+T/C/K, Cmd+Shift+Option+C (alongside Ctrl+Number).
- [x] 1.2 Cmd+W unloads (not removes) pinned/favourite tabs; regular tabs removed + remembered.
- [x] 1.3 Cmd+Shift+T reopen stack; Cmd+D pin toggle; Cmd+Shift+K clear unpinned.
- [x] 1.4 Edit menu (Undo/Redo/Cut/Copy/Paste/Select All) for standard Cmd A/C/V/X/Z.

## 2. Command palette (Cmd+N)

- [x] 2.1 `CommandPalette` overlay: field + results (smart URL/search primary, open tabs, history); keyboard nav; scrim close.
- [x] 2.2 `HistoryStore` (persisted, deduped, capped); recorded on navigation.
- [x] 2.3 Execute: switch-to-tab / open URL (new tab) / DuckDuckGo search.

## 3. Copy/share toast

- [x] 3.1 Top-right, workspace-tinted toast; slide-in/out animation; replaces prior toast.
- [x] 3.2 Filled-accent Share button → `NSSharingServicePicker` (AirDrop/Mail/…); haptic + press flash.
- [x] 3.3 Stays while hovered / while share sheet open (pin + picker delegate release).

## 4. Ship

- [x] 4.1 Full suite green; ship PR-gated; update `CLAUDE.md`.
