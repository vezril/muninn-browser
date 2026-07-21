# Proposal: split-view

## Why

Arc's Split View — view multiple tabs at once. Useful for comparing/referencing pages side
by side without tab-switching.

## What Changes

- **Split view content:** 2–4 regular tabs render side by side in an `NSSplitView` (draggable,
  resizable dividers). Each pane is a rounded card with the live page; the active pane has an
  accent border and a hover **×** to leave the split.
- **Combined sidebar tab:** a split renders as **one** bordered sidebar entry containing a
  per-member mini-chip (favicon + title + ×). Clicking a mini-chip focuses that pane; the group
  highlights when it's the active view.
- **Create / modify:**
  - **Drag a regular tab onto the center** of another (full-border drop zone) → split them.
    Edge drops still reorder (insertion line). Dragging a member out reorders it out of the split.
  - Right-click → **Add to Split View** / **Remove from Split View**.
- **Close semantics:** closing a split member (its ×, or Cmd+W / Close on it) **removes it from
  the split** rather than closing the tab; the last remaining member dissolves the group.
- Model: `BrowserTab.splitGroupId` (session-only, regular tabs). New tabs / workspace switches
  collapse to single view. Address/back/forward/reload act on the active pane.

## Impact

`BrowserTab.splitGroupId` + a 3-zone (`before`/`after`/`onto`) drop in `TabChipView`; `AppShell`
gains the split renderer (`NSSplitView` panes), combined chip, add/remove/drop-split, and
group-aware close/move/select/context-menu.
