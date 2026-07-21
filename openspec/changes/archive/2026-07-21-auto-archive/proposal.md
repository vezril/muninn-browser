# Proposal: auto-archive

## Why

Arc's Auto-Archive — clean as you go. Close regular tabs left idle past a threshold so the tab
list stays tidy, with a one-click "Clear" for the unpinned tabs.

## What Changes

- **Auto-Archive:** each tab tracks `lastActiveAt` (updated when foregrounded). Regular,
  ungrouped tabs idle past the configured interval are auto-closed — **exempt:** the active tab,
  pinned/favourites, split members, and the Mini Player tab. Archived tabs stay reopenable via
  Cmd+Shift+T / history. Sweep runs every ~5 min and on each tab switch.
- **Setting:** Settings gear → **Auto-Archive Tabs ▸** Never / 12 Hours / **1 Day** (default) /
  7 Days / 30 Days (`AutoArchive.current`, persisted).
- **Clear button:** the separator between pinned/favourites and regular tabs gets a small
  **"↓ Clear"** button (right side; ↓ = the unpinned tabs below) that closes all unpinned tabs in
  the workspace. Shown only when there are unpinned tabs.

## Impact

`AutoArchive` setting; `BrowserTab.lastActiveAt`; `AppShell` gains `archiveStaleTabs()` + a timer
+ the Auto-Archive submenu; `separatorLine(showClear:)` with the Clear button (→ existing
`clearUnpinnedTabs`).
