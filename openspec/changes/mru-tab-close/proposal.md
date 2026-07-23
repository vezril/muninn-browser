# Proposal: mru-tab-close

Fix: closing the active tab (⌘W) jumped to the **top of the tab list** instead of the previously-used tab.

## Cause & fix

`closeTab` selected `tabs.firstIndex { workspace match }` — literally the first tab. It now selects the
**most-recently-used** remaining tab in the workspace, using the `lastActiveAt` timestamp tabs already
track (from auto-archive): the remaining tab with the newest `lastActiveAt` is the one used just before
the closed one. The newly-active tab is re-stamped so the MRU chain stays correct across repeated closes.
Matches Chrome/Safari.

## Impact

One-branch change in `AppShell.closeTab`. No new state. 110 XCTests green; live-gated.
