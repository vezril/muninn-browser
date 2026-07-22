# Proposal: video-download

One-click video downloading, plus two fixes found along the way (Library right-click menu; settings
button hit-testing).

## 1. Video download (yt-dlp)

A blue **⬇ button** appears in the address row **only on known video sites** (YouTube, Vimeo, Facebook,
Instagram, TikTok, X, Twitch, Reddit, Dailymotion, Bilibili, Streamable) — it collapses to zero width
elsewhere. Click → download the current page's video; **right-click** → Video or **Audio Only (MP3)**.

`VideoDownloader` shells out to **yt-dlp** (+ **ffmpeg** to mux) — the only realistic way to handle
adaptive streams + rotating ciphers across 1000+ sites. It parses `--newline` progress and captures the
final path via `--print after_move:filepath`. A `VideoDownloadHUD` (title, live %, bar, cancel ×) stacks
at the web card's bottom-right; on finish the file drops into the **Library** (recorded + animation), and
failures surface yt-dlp's reason. Saves to the tab's profile download folder.

**YouTube 403 fix:** YouTube's *default* player client hands out DASH URLs that intermittently return
HTTP 403. The download uses `--extractor-args "youtube:player_client=web_safari,default,tv"` — `web_safari`
returns 403-resistant formats at full resolution without a PO token (only affects the youtube extractor).
Plus `--retries 5 --fragment-retries 5`. The exact invocation was validated end-to-end (download → mux →
final path) against real videos.

**Dependency:** requires yt-dlp & ffmpeg (Homebrew). If yt-dlp is absent the button hides and the action
shows an install hint. (Note: downloading may violate a site's ToS; the user is responsible for the rights
to what they save.)

## 2. Library right-click menu

Right-clicking a download (Downloads list or Media grid) now offers **Open / Show in Finder / Copy Path /
Move to Trash / Remove from List**. File-ops disable when the file is missing; "Move to Trash" uses
`NSWorkspace.recycle` (recoverable) and drops it from the list.

## 3. Settings button hit-testing (two bugs)

The gear did nothing on click. Two overlapping causes fixed:
- The **sidebar resize splitter** ran from the window top, overlaying the nav strip and stealing the
  rightmost button's clicks (hover still fired — tracking areas aren't occluded like clicks). It now
  starts **below** the nav cluster.
- At narrow sidebar widths the nav cluster **overflowed the sidebar's right edge**, pushing the gear's
  right half outside the sidebar bounds (not hit-testable). The cluster was tightened (icon buttons
  24→22px, tighter spacing, smaller left inset) so it fits within the **minimum** width. The gear also now
  opens the **Settings window** directly (the old `NSMenu.popUp` dropdown was legacy/redundant).

## Impact

New: `Muninn/VideoDownloader.swift`, `Muninn/VideoDownloadHUD.swift`. Edits: `AppShell` (video button +
HUD stack + download flow + host detection; splitter top inset; nav-cluster tightening; gear →
`openSettings`), `LibraryPane` (download context menu). 103 XCTests green; yt-dlp invocation validated
end-to-end; live-gated (download incl. the 403 fix, Library menu, settings button at narrow widths).
