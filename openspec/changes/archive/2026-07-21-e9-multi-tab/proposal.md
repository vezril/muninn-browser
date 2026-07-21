# Proposal: e9-multi-tab

## Why

Muninn's shell was single-tab — not usable for daily browsing. The first step toward
Calvin's daily-driver goal (iterate on design/features/bugs in real use) is multi-tab
browsing. (Auth-fork login is parked; this is independent shell work — roadmap E9.)

## What

- **`BrowserTab`** — one tab = an injected `WKWebView` (Pass content shim per-tab, via a
  distinct broker context `page-<id>`) + title/url tracking.
- **`AppShell`** refactored from one `page` to `[BrowserTab]` + active index: a **tab bar**
  (chips with title + close, a `+` button), tab **new/close/switch**, per-tab title, and
  the address field + back/forward/reload driven by the **active** tab.
- **Keyboard shortcuts:** Cmd-T (new), Cmd-W (close), Cmd-L (focus address), Cmd-R (reload).
- `InjectionCoordinator` gains a `contextName` param so each tab registers a unique push
  context (native→page delivery targets the right tab).

## Scope / cutline

MVP tabs: open/close/switch, address+nav on active tab, keyboard shortcuts, per-tab title.
**Deferred:** favicons, drag-reorder, tab overflow/scroll, session restore, cmd-clicking
links into new tabs, per-tab loading spinners (later E9 polish).

## Impact

New `BrowserTab`; `AppShell` rewritten for tabs (auth-fork/gate wiring preserved, now on
the active tab); `InjectionCoordinator.contextName`. No change to the shim/bus internals.
