# Proposal: quick-look

## Why

Arc's "Little Arc" pattern — a lightweight, ephemeral window for a quick lookup you then
**triage**: glance, then toss it or promote it to a real tab. Keeps throwaway pages out of
the main workspace.

## What Changes

- **`QuickLookWindow`** ("Little Muninn") — a compact 480×660 window with minimal chrome
  (back/forward + address/search field + "Open in Muninn" + close), hosting a WKWebView that
  carries the Pass shim via the **shared** background host (same broker as the main window).
  - Address field: type a URL or a search (DuckDuckGo default).
  - **Triage:** Esc / close **dismisses** (no tab left behind); **Open in Muninn** promotes the
    current page to a new tab in the main window and closes the Quick Look.
- **Triggers:**
  - **Cmd+Option+N** / File → New Quick Look (works from any window, via the menu).
  - **Default browser:** Muninn registers as an http/https handler (`Info.plist`
    `CFBundleURLTypes`); external links route through `AppDelegate.application(_:open:)` into a
    Quick Look. A **Set as Default Browser…** menu item requests the OS default (falls back to
    pointing at System Settings).
- Main-window shortcuts are **gated to the main window**, so Cmd+W / Esc inside a Quick Look
  act on the Quick Look, not the main tabs.

## Impact

New `QuickLookWindow`; `AppShell` gains `openQuickLook` / promote-to-tab + key-monitor gating;
`AppDelegate` gains URL-open handling, a File menu, and Set-as-Default-Browser; a partial
`Info.plist` (merged with the generated one) declaring http/https handling.
