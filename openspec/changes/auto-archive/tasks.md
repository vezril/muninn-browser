# Tasks: auto-archive

## 1. Auto-Archive

- [x] 1.1 `BrowserTab.lastActiveAt` (updated on foreground); `AutoArchive` setting (Never/12h/1d/7d/30d, persisted, default 1d).
- [x] 1.2 `archiveStaleTabs()` closes idle regular/ungrouped non-active tabs (exempt: pinned/fav/split/mini); sweep on tab switch + a ~5-min timer. Settings → Auto-Archive submenu.

## 2. Clear button

- [x] 2.1 `separatorLine(showClear:)` — a "↓ Clear" button on the right of the pin/regular separator → `clearUnpinnedTabs`; shown only when there are unpinned tabs.

## 3. Ship

- [x] 3.1 Full suite green; ship PR-gated; update `CLAUDE.md`; cut version.
