# Tasks: split-view

## 1. Split content

- [x] 1.1 `showVisibleTabs` renders 1 (single rounded web view) or 2–4 (NSSplitView) panes from the active tab's group.
- [x] 1.2 Pane = rounded card + active accent border + hover × (removes from split).

## 2. Combined sidebar tab

- [x] 2.1 A split group renders as one bordered chip with per-member mini-chips (favicon + title + ×); active-group + active-member highlight.
- [x] 2.2 Clicking a mini-chip focuses that pane; regular non-group tabs render as normal chips.

## 3. Create / modify / close

- [x] 3.1 `splitGroupId` on `BrowserTab`; add/remove/drop-split; groups dissolve at ≤1 member.
- [x] 3.2 Drag onto center (3-zone drop) splits; edge reorders; dragging a member out leaves the split.
- [x] 3.3 Right-click Add/Remove from Split View; close of a split member = remove-from-split.
- [x] 3.4 New tab / workspace switch / reclassify collapse or leave the split.

## 4. Ship

- [x] 4.1 Full suite green; ship PR-gated; update `CLAUDE.md`.
