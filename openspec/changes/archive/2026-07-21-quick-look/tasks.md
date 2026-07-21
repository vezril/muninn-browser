# Tasks: quick-look

## 1. Quick Look window

- [x] 1.1 `QuickLookWindow`: compact window, shared-broker `InjectionCoordinator`, back/forward + address/search field + "Open in Muninn" + close; title/url tracking.
- [x] 1.2 Address field loads a URL or DuckDuckGo search; Esc / Cmd+W close (own key monitor while key).
- [x] 1.3 Promote: "Open in Muninn" opens the current URL as a tab in the main window + surfaces it, then closes.

## 2. Triggers

- [x] 2.1 Cmd+Option+N / File → New Quick Look (menu key-equivalent, works from any window).
- [x] 2.2 Default browser: `Info.plist` `CFBundleURLTypes` (http/https); `AppDelegate.application(_:open:)` → Quick Look (queues pre-launch URLs); Set as Default Browser… menu item.
- [x] 2.3 Gate main-window shortcuts to the main window so Quick Look keys don't hit the main tabs.

## 3. Ship

- [x] 3.1 Full suite green; ship PR-gated; update `CLAUDE.md`.
