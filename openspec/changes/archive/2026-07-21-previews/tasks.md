# Tasks: previews

## 1. Hover preview

- [x] 1.1 Favourite icons get `onHover` → schedule show (~0.5s) / close (grace) with cancellation.
- [x] 1.2 `NSPopover` (applicationDefined) anchored to the icon hosts a reused `InjectionCoordinator` web view loading the favourite's URL; hovering the popover keeps it open.
- [x] 1.3 Close blanks the reused web view (`about:blank`) to free the page.

## 2. Ship

- [x] 2.1 Full suite green; ship PR-gated; update `CLAUDE.md`.
