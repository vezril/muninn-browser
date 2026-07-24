# Tasks: media-controls

## 1. Global commands
- [x] 1.1 `ShortcutAction.pauseAllVideos` / `.muteAllTabs` (+ titles, defaults ⌘⇧P / ⌘⇧M), remappable via `ShortcutStore`.
- [x] 1.2 `AppShell.pauseAllVideos()` — sweeps every tab (main document + same-origin subframes), pauses playing media, toasts the real count ("Paused N videos" / "Nothing was playing").
- [x] 1.3 `AppShell.toggleMuteAllTabs()` — session-wide mute; new/lazily-loaded tabs inherit it (`applyMuteIfNeeded` from `makeTab`).
- [x] 1.4 Surfaced in the File menu + the ⌘N command palette + the key monitor.

## 2. Whole-page mute
- [x] 2.1 `WKWebView.setPageMuted(_:)` — private SPI `_setPageMuted:` (`_WKMediaMutedState` audio bit), fails soft to a JS media-element mute. Covers Web Audio + later-started sound.
- [x] 2.2 `BrowserTab.isMuted` + `setMuted(_:)` as the per-tab source of truth.

## 3. Per-tab audio indicator
- [x] 3.1 Speaker icon in `makeTabChip`, shown ONLY while `tab.isPlayingMedia`; slashed when muted; click toggles that tab's mute.
- [x] 3.2 Sidebar refreshes when a tab's playing state changes (`onMediaState`), and after Mute All Tabs.

## 4. Ship
- [x] 4.1 Verified live (Calvin): both commands work; the speaker appears while playing, mutes/unmutes the tab, and disappears on stop.
- [x] 4.2 121 tests green; version bumped + tagged.

## Follow-ups (not in this change)
- [ ] Persist per-tab mute across relaunch.
- [ ] Debounce the sidebar refresh if rapid play/pause (ads, buffering) ever causes visible flicker.
- [ ] Gate the private `_setPageMuted:` behind a build flag if a Mac App Store build is ever attempted.
