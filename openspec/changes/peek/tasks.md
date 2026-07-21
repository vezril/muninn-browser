# Tasks: peek

## 1. Interception

- [x] 1.1 `InjectionCoordinator.onNavigationAction` (`@MainActor` `decidePolicyFor`) + `onCreateWebView` (`WKUIDelegate.createWebViewWith`).
- [x] 1.2 `BrowserTab.homeURL` set on pin/favourite + restore; cleared back to regular.
- [x] 1.3 `AppShell.decideNavigation`: pinned/favourite + `.linkActivated` + cross-site → cancel + Peek (deferred to next tick); `target="_blank"` → Peek (pinned, cross-site) or new tab.

## 2. Peek overlay

- [x] 2.1 `PeekOverlay`: in-window preview, slide-in from right, dim scrim; shim-injected web view (shared host).
- [x] 2.2 Slim bar: title + Open in Tab (promote) + close; Esc / × / dim-click dismiss; navigating main content dismisses.

## 3. Ship

- [x] 3.1 Full suite green; ship PR-gated; update `CLAUDE.md`.
