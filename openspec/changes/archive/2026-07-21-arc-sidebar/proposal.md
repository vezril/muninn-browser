# Proposal: arc-sidebar

## Why

Daily-driver ergonomics Calvin wants from Arc: favourites, pinned tabs, folders, and
workspaces in the vertical sidebar — so tabs are organized and persistent, not just an
ephemeral list. Built on the v0.1.0 multi-tab shell (`e9-multi-tab`).

## What (incremental)

1. **Foundation:** tab *kinds* — `favourite` / `pinned` / `regular`. Sidebar renders three
   sections top-to-bottom (favourites as larger icons → pinned chips → **separator line** →
   regular chips → New Tab). Right-click a tab → Pin / Add to Favourites / Unpin / Close.
   **Persistence** (favourites + pinned survive relaunch, restored lazily). Favourites use
   letter/colour avatars (privacy-first: no third-party favicon fetch; real favicons later).
2. **Folders:** collapsible, renamable, colourable groups for pinned tabs; drag pins in/out.
3. **Workspaces:** switch between spaces; each has its own pinned + favourites (regular tabs
   too); a workspace switcher in the sidebar.

## Scope / cutline

Increment 1 first (this build), then 2 and 3. Deferred: real favicons, drag-reorder within a
section (folders get drag), tab archiving/sleep, sync.

## Impact

`BrowserTab.kind`; a `SidebarModel` (sections/persistence, later folders/workspaces); the
sidebar UI grows sections + context menus. Persistence via a JSON file in Application Support.
