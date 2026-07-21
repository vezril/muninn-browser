# Proposal: developer-mode

## Why

Muninn is a from-scratch WKWebView browser; building and dogfooding it needs the same
dev affordances every browser has — **View Page Source** and **Inspect Element / dev
console**. Arc ships these behind a "Developer Mode". WKWebView makes this non-trivial:
there is **no public API to open the Web Inspector in-app** (the public `isInspectable`
only enables *remote* attach from Safari's Develop menu). Getting an in-app inspector
requires private WebKit API.

## What

A **Developer Mode** toggle (Settings → Advanced, off by default) that, when on:

- Adds **View Page Source** and **Inspect Element** to the right-click menu, and the
  **⌥⌘U** / **⌥⌘I** shortcuts.
- **View Page Source** opens the page's serialized HTML in a new tab.
- **Inspect Element** opens the real, Safari-grade **Web Inspector in-app** (elements /
  console / network / sources), as its own detached window.

## How (the WKWebView specifics)

- `MuninnWebView : WKWebView` overrides `willOpenMenu` to add the dev items (only in
  Developer Mode).
- The in-app inspector uses **private WebKit API** — `WKWebView._inspector` → `-show` —
  which requires **developer extras** enabled on the config's `WKPreferences`
  (`setValue(true, forKey: "developerExtrasEnabled")`, set at web-view creation in Developer
  Mode). `isInspectable` alone is insufficient for the local frontend.
- **Detach is mandatory in our window.** WebKit opens the inspector *docked*, reparented as
  a sibling inside the inspected view's superview — which here is our clipping, layout-managed
  rounded web card — so a docked inspector renders **blank and flickers** (two layout systems
  fighting over autoresizing frames). We force detached: poll the inspector's `isVisible`
  (WebKit sets it after the frontend loads) then call `-detach`, which also **persists**
  `InspectorStartsAttached = NO`. We additionally **pre-seed** that WebKit default at launch
  (`__WebInspectorPageGroupLevel1__.WebKit2InspectorStartsAttached = false`) so even the first
  open is detached with no docked flash. (Root-caused with the webkit-developer agent against
  WebKit source: `WebInspectorUIProxyMac.mm::platformAttach`.)

## Scope / non-goals

- No custom in-app console panel — we use the real WebKit inspector.
- Docked-inspector support is out of scope (our card clips it); we always detach.

## Ground rules / risk

- **Off by default** — the private symbols (`_inspector`, `developerExtrasEnabled`) are only
  touched once the user opts in; the whole path fails closed (a missing symbol → no-op, never
  a crash), and the public `isInspectable` + Safari Develop-menu route still works.
- **App Store note:** these are private WebKit symbols and would trip MAS static-symbol review.
  Muninn is not yet MAS-distributed; when it is, gate this path behind a build flag (the
  sanctioned Release path is `isInspectable` + Safari remote attach, no in-app window).
  Recorded here so the decision is explicit. (Calvin chose the private-API in-app inspector
  over the public-only fallback, 2026-07-21.)

## Impact

New `MuninnWebView` (all web views become this subclass via `InjectionCoordinator`);
`AppSettings.developerMode`; a Developer Mode toggle in Settings → Advanced; `viewSource`
+ dev shortcuts in `AppShell`. No shim/background changes. Existing tests unaffected.
