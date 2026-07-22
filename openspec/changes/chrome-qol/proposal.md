# Proposal: chrome-qol

A batch of cosmetic + quality-of-life refinements to the browser chrome and input handling.

## Settings

- The Settings top nav (now 10 sections after Extensions) was cramped/clipping off the window.
  Widened the window (700 → 840) and tightened the nav buttons so all sections fit.

## Top-bar cluster

- Moved **shield + settings + extension action buttons** into their own cluster on the **top bar**,
  to the right of the nav cluster (toggle/back/forward/reload), with a **vertical divider** between
  the two clusters. The address field below is now **full width**.
- The top bar sizes to its content (no compressing trailing constraint) so buttons never overlap;
  nav offset trimmed (88 → 80), buttons tightened, default sidebar widened (230 → 284) to fit.
  Extension buttons sit rightmost so they clip before the fixed controls on a narrow sidebar.

## Address field

- Forced **single-line** (no wrap, truncates, scrolls horizontally while editing).
- Added a **Share** button inside the URL box's right edge → the standard macOS share sheet
  (`NSSharingServicePicker`) for the current page.

## Resizable panes

- The **left sidebar** and **right Tools sidebar** are now resizable by dragging their inner edge
  (a `SplitterHandle` with the resize cursor). Widths are clamped and **persisted** to `sidebar.json`.

## Mouse

- **Side buttons** (mouse buttons 3/4) navigate **back/forward** on the active tab.
- **Middle-click** on **back/forward/reload** performs that action in a **background tab** (current
  tab preserved); on **reload** it duplicates the current page.
- **Middle-click a link** opens it in a **background tab** (injected `auxclick` listener resolves the
  anchor href and hands it to the shell, bypassing Peek).

## Hover + motion

- All chrome icon buttons (nav, shield, settings, extensions, tools, library) now share the
  `HoverIconButton` hover cue (rounded highlight + pointing hand); dynamic tints (shield orange,
  tools accent) persist across hover via `restingTint`.
- Opening a new tab plays a subtle fade + rise on the new page content.

## Impact

New `SplitterHandle`; chrome buttons → `HoverIconButton`; top-bar restructure in `AppShell.buildUI`;
resize + share + middle-click handlers; `InjectionCoordinator` gains a middle-click link channel;
`SidebarState` persists `sidebarWidth`/`toolsWidth`. UI-only; 81 XCTests remain green.
