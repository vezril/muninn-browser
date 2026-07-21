# Tasks: e9-multi-tab

## 1. Per-tab context + tab model

- [x] 1.1 `InjectionCoordinator(contextName:)` — each tab registers a distinct broker push context (`page-<id>`); threaded through `registerContext`/`unregisterContext` and the port `from:` name.
- [x] 1.2 `BrowserTab` — wraps an `InjectionCoordinator`; tracks title (page title → host → "New Tab") and url via KVO; `onChange` callback.

## 2. AppShell multi-tab

- [x] 2.1 `AppShell` holds `[BrowserTab]` + active index; address field + back/forward/reload + `navigate` drive the ACTIVE tab; the auth-fork/gate wiring preserved (runs on the active tab).
- [x] 2.2 Tab bar UI (chips: title button + `×` close; `+` new-tab button), rebuilt on change; active-tab highlight; `showActiveWebView` swaps the container's webview.
- [x] 2.3 `newTab` / `closeTab` (last tab closes the window) / `selectTab`.
- [x] 2.4 Keyboard shortcuts (local monitor): Cmd-T / Cmd-W / Cmd-L / Cmd-R.

## 3. Verify & ship

- [x] 3.1 Full suite green (multi-tab refactor + contextName didn't regress the shim/bus).
- [ ] 3.2 Live check: launch, open/close/switch tabs, navigate in each, shortcuts work (GUI — warn Calvin per ground rule 2).
- [ ] 3.3 Ship PR-gated; update `CLAUDE.md` (shell is now multi-tab).
