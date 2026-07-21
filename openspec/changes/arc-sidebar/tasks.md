# Tasks: arc-sidebar

## 1. Foundation — kinds, sections, pin/favourite, persistence

- [x] 1.1 `TabKind` (favourite / pinned / regular) on `BrowserTab`; a `savedURL` for restore.
- [x] 1.2 Sidebar renders 3 sections: favourites (larger letter/colour-avatar icons, wrapping row) → pinned (chips) → **separator line** → regular (chips) → New Tab. Empty sections hide.
- [x] 1.3 Right-click a tab → context menu: Add to Favourites / Pin Tab / Unpin / Remove from Favourites / Close Tab (moves the tab between sections).
- [x] 1.4 Persistence: save favourites + pinned (url, title, kind, order) to a JSON file in Application Support; restore on launch (tabs created; loaded lazily on first select). Regular tabs are session-only for now.
- [x] 1.5 Live check (GUI — warn Calvin): pin/favourite via right-click, sections + separator, survives relaunch.
- [x] 1.6 Favicons: each site's own favicon (from its origin) on tab chips + favourite tiles; cached + persisted.

## 2. Folders + drag & drop

- [x] 2.1 `Folder` (name, colour, collapsed) grouping pinned tabs; collapsible/renamable/colourable rows; move pins in/out. Persisted. Coloured header rows.
- [x] 2.2 Drag & drop: reorder tabs within a section; drag tabs between sections (in/out of favourites, pins, folders); reorder folders; drop onto a folder header to add. Insertion-line indicator. "Add to Folder" in the context menu for any tab.

## 3. Workspaces (later)

- [ ] 3.1 `Workspace` (name, colour) owning its favourites + pinned (+ regular); a switcher in the sidebar; switching swaps the visible sets. Persisted; remembers the active workspace.

## 4. Ship

- [ ] 4.1 Full suite green; ship PR-gated; update `CLAUDE.md`.
