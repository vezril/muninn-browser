# Proposal: media-controls

## Why

Browsing with many tabs open means sound you didn't ask for: an autoplaying video two
workspaces away, an ad that starts talking, a background tab you can't find. Muninn had no way
to silence or stop media except hunting the offending tab by hand. Chrome/Safari solve the
"which tab is making noise?" half with a per-tab audio indicator; nothing solved the "shut
everything up right now" half.

## What

Two global commands plus a per-tab control:

- **Pause All Videos** (⌘⇧P) — pauses every playing `<video>`/`<audio>` across all tabs in all
  workspaces, sweeping the main document and same-origin subframes. One-shot; reports how many it
  actually paused.
- **Mute / Unmute All Tabs** (⌘⇧M) — toggles a whole-page mute on every tab. Session-wide, so
  newly opened/lazily-loaded tabs inherit the muted state.
- **Per-tab audio indicator** — a speaker icon appears in a tab's sidebar row (after the favicon)
  **only while that tab is playing media**; clicking it mutes/unmutes just that tab (slashed
  speaker when muted). Disappears when playback stops. Stays in sync with Mute All Tabs.

Both commands are remappable (Settings → Shortcuts) and reachable from the File menu and the ⌘N
command palette.

## Implementation notes

- Muting is a **whole-page** mute via the private SPI `-[WKWebView _setPageMuted:]`
  (`_WKMediaMutedState` audio bit), so it covers `<video>`, `<audio>`, and Web Audio, and survives
  the page starting new sound. Fails soft: if the symbol is absent it falls back to muting existing
  media elements via JS. ⚠️ Private symbol — gate out for any Mac App Store build (same posture as
  the in-app Web Inspector).
- The audio indicator reuses the existing Mini Player media probe (`onMediaState`); the sidebar
  refreshes only when a tab's playing state actually changes.

## MVP cutline

Media in a **cross-origin** iframe is not script-controllable (by anyone), so Pause All Videos
can't reach it; the page-level mute still silences it. Per-tab mute state is session-only (not
persisted across relaunch).
