# Proposal: tab-rename-and-ad-cosmetics

Three small daily-driver improvements.

## Rename tabs

A user-chosen name that overrides the page title in the sidebar, without touching the tab's content
(the page title keeps updating underneath; the sidebar just shows the custom name). `BrowserTab`
gains `customTitle` + `displayTitle` (custom, else live page title); the sidebar rows/chips/tooltip
use `displayTitle`. Right-click a tab → **Rename…** (a text prompt), and **Reset Name** when a custom
name is set. Persisted for pinned/favourite tabs (`SavedTab.customTitle`), so it survives relaunch.

## Pinned tabs reopen at their pin

A pinned/favourite tab is anchored to its pin (`homeURL`). Previously, navigating away then closing
(Cmd+W unloads it) reopened at the last-visited URL. Now closing snaps it back to the original pinned
link: `unload()` sets `pendingURL = homeURL`, and `saved()` persists the pin (`homeURL`) so it also
reopens at the pin after a relaunch. Regular tabs are unaffected (keep their current spot).

## Cosmetic ad hiding (Shields)

Network-level ad blocking stops the ad loading, but pages often leave the empty slot behind — a blank
white bar (e.g. AdThrive's sticky footer). `AdCosmetics.script()` injects a small stylesheet hiding
common ad-slot containers (`.adthrive-ad` — on every AdThrive/Raptive slot — plus Google Ad
Manager/AdSense slots), so no empty space remains. Injected when Shields "Block ads & trackers" is on;
`*.proton.me` exempt. CSS handles dynamically-inserted slots automatically.

## Impact

`BrowserTab` (`customTitle`/`displayTitle`, anchored `unload`/`saved`); `SavedTab.customTitle`;
`AppShell` rename menu + handlers, `displayTitle` in the sidebar, restore carries `customTitle`; new
`AdCosmetics`; `InjectionCoordinator` injects it under `blockAds`. 86 XCTests green.
