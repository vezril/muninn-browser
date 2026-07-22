# Tasks: video-download

## Video download
- [x] `VideoDownloader` — yt-dlp+ffmpeg process, `--newline` progress parse, `after_move:filepath` capture,
      MP3 option, cancel; `@unchecked Sendable` with serialized IO queue.
- [x] YouTube 403 fix: `player_client=web_safari,default,tv` + retries; validated end-to-end.
- [x] `VideoDownloadHUD` — title/percent/bar/cancel; stacked bottom-right.
- [x] `AppShell` — contextual video button (collapses off video sites); download flow → Library record +
      animation; MP3 via button right-click menu; yt-dlp-missing hint.
## Library
- [x] Right-click menu on downloads + media: Open / Show in Finder / Copy Path / Move to Trash / Remove.
## Settings button
- [x] Splitter starts below the nav cluster (no longer steals the gear's clicks).
- [x] Nav cluster tightened to fit inside the minimum sidebar width (gear fully hit-testable).
- [x] Gear opens the Settings window directly.
## Ship
- [x] Build clean; full suite green (103); live-gated (video incl. 403, Library menu, settings button).
