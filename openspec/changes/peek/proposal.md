# Proposal: peek

## Why

Arc's Peek — clicking a cross-site link in a pinned/favourite tab shouldn't navigate the
anchored tab away from its home site. Instead it opens the link in a quick preview you can
dismiss or promote. Keeps pinned tabs anchored.

## What Changes

- **`homeURL`** on pinned/favourite tabs — the site they're anchored to (set on pin/favourite
  and on restore).
- **Navigation interception:** in a pinned/favourite tab, a **cross-site** main-frame link
  click (`decidePolicyFor`, `.linkActivated`) — or a `target="_blank"` / `window.open` (via
  `WKUIDelegate.createWebViewWith`) — is intercepted and opened in a **Peek** instead of
  navigating the tab. Same-site links still load in the tab. (Regular tabs: `target="_blank"`
  opens a normal new tab.)
- **`PeekOverlay`** — an in-window preview panel that slides in from the right, dimming the
  anchored tab; slim bar with title, **Open in Tab** (promote to a real tab), and close. Esc /
  × / clicking the dimmed area dismisses; navigating the main content also dismisses it. Carries
  the Pass shim via the shared background host.

## Impact

`InjectionCoordinator` gains `onNavigationAction` (a `@MainActor` policy hook — the SDK's
`decisionHandler` is `WK_SWIFT_UI_ACTOR`) + `onCreateWebView` (WKUIDelegate); `BrowserTab.homeURL`;
`AppShell` gains `decideNavigation` + Peek show/hide; new `PeekOverlay`. The Peek is created on
the next runloop tick (creating a web view inside the policy callback re-enters WebKit).
