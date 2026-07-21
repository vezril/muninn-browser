# Tasks: mini-player

## 1. Media detection

- [x] 1.1 Isolated-world probe (`play`/`playing`/`pause`/`ended`, no readyState gate so the initial play counts) → `muninnMedia` handler → `onMediaState` → `BrowserTab.isPlayingMedia`.

## 2. Pop-out + window

- [x] 2.1 `MiniPlayerWindow`: titled/chromeless always-on-top window; native drag + edge-resize; borrows the tab's web view.
- [x] 2.2 `popOutIfPlaying` on switching away from a still-playing tab — wired into selectTab, newTab (Cmd+T), and workspace switch.
- [x] 2.3 Video-only: reparent the `<video>` into a root fullscreen wrapper, `!important` sizing so it scales.

## 3. Controls

- [x] 3.1 Play/pause, return-to-tab (reclaim), close (pause). Click the video to toggle (`acceptsFirstMouse`).
- [x] 3.2 Icon flash (⏸/▶) rendered in the web view; button press flash + haptic.

## 4. Ship

- [x] 4.1 Full suite green; ship PR-gated; update `CLAUDE.md`.
