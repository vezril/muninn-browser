# Tasks: arc-sidebar

## 1. Foundation — kinds, sections, pin/favourite, persistence

- [ ] 1.1 `TabKind` (favourite / pinned / regular) on `BrowserTab`; a `savedURL` for restore.
- [ ] 1.2 Sidebar renders 3 sections: favourites (larger letter/colour-avatar icons, wrapping row) → pinned (chips) → **separator line** → regular (chips) → New Tab. Empty sections hide.
- [ ] 1.3 Right-click a tab → context menu: Add to Favourites / Pin Tab / Unpin / Remove from Favourites / Close Tab (moves the tab between sections).
- [ ] 1.4 Persistence: save favourites + pinned (url, title, kind, order) to a JSON file in Application Support; restore on launch (tabs created; loaded lazily on first select). Regular tabs are session-only for now.
- [ ] 1.5 Live check (GUI — warn Calvin): pin/favourite via right-click, sections + separator, survives relaunch.

## 2. Folders (later)

- [ ] 2.1 `Folder` (name, colour, collapsed) grouping pinned tabs; collapsible/renamable/colourable rows; move pins in/out. Persisted.

## 3. Workspaces (later)

- [ ] 3.1 `Workspace` (name, colour) owning its favourites + pinned (+ regular); a switcher in the sidebar; switching swaps the visible sets. Persisted; remembers the active workspace.

## 4. Ship

- [ ] 4.1 Full suite green; ship PR-gated; update `CLAUDE.md`.
