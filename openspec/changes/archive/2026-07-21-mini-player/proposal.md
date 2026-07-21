# Proposal: mini-player

## Why

Arc's Mini Player — keep watching/listening while you browse. When you switch away from a tab
that's playing media, its video pops into a small floating window so it keeps playing.

## What Changes

- **Media detection:** an isolated-world probe reports play/pause (capture-phase `play`,
  `playing`, `pause`, `ended`) per tab via a `muninnMedia` handler → `BrowserTab.isPlayingMedia`.
- **Pop-out:** switching away from a still-playing tab (select another tab, **Cmd+T**, or a
  workspace switch) borrows that tab's live web view into a **`MiniPlayerWindow`** — a titled,
  chromeless, always-on-top window. Media keeps playing (audio + video).
- **Video-only:** the playing `<video>` is reparented into a fullscreen wrapper at the document
  root (survives transformed ancestors like YouTube) and sized with `!important` rules so it
  scales with the window and shows only the video.
- **Controls:** native drag (title-bar strip) + edge-resize; a control bar with play/pause,
  return-to-tab (reclaims the web view), and close (pauses). Click the video to toggle, with a
  DOM icon-flash (⏸/▶) rendered *in the web view* (an AppKit overlay won't composite above
  WKWebView). Buttons flash + haptic on press. `acceptsFirstMouse` so the first click counts.
- Returning to the tab / closing / new tab collapses the Mini Player and restores the page.

## Impact

`InjectionCoordinator` gains `onMediaState` + a media-probe user script + `muninnMedia` handler;
`BrowserTab.isPlayingMedia`; new `MiniPlayerWindow`; `AppShell` gains the Mini Player manager,
video-only enter/exit JS, and `popOutIfPlaying` wired into select/new-tab/workspace-switch.
