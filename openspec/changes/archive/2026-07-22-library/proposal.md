# Proposal: library

## Why

Downloads were saved to a folder but never surfaced in-app — no history, no way to find them.
This adds a **Library** (scoped to Downloads + Media, per Calvin) as their home.

## What

- **Download tracking** — a `DownloadStore` records each finished download (filename, path,
  source, date, size) to `downloads.json`. Hooked into the `WKDownloadDelegate` via a new
  `onDownloadFinished`.
- **Tracked "Save Image" / "Download Linked File"** — WebKit's native context-menu save
  **bypasses `WKDownloadDelegate`**, so right-click saves never recorded. We inject a `contextmenu`
  listener that captures the clicked image/link, add our own **tracked** menu items (routing
  through `WKWebView.startDownload`), and **remove WebKit's native "Download Image"**.
- **Library pane** — a **left-side overlay** that slides in over everything, **workspace-tinted**
  with **rounded corners** + shadow. **Downloads** (list: icon, name, source · size · date;
  double-click opens; hover → reveal-in-Finder / remove) and **Media** (image/video/audio
  downloads as a thumbnail grid). Click-outside / × / button-toggle dismisses.
- **Sidebar button** — a 📚 button at the bottom-left, beside the workspace switcher, with a
  **hover cue** (highlight + pointing-hand). Finishing a download plays a **drop animation** (a
  file icon falls straight down into the button, which flashes).

## Impact

New: `DownloadStore`/`DownloadRecord`, `LibraryPane`, `HoverIconButton`; `InjectionCoordinator`
gains download tracking + a context-menu capture handler + `startDownload`; `MuninnWebView` gains
the download menu items; `AppShell` gains the sidebar button, the pane, and the animation. No
persistence beyond `downloads.json`; downloads are tracked going forward.

## Non-goals

- No archived-tabs / easels / boosts (only Downloads + Media, per request).
- Media = the image/video/audio files among downloads (matching Arc's Media section), not a
  page-media capture system.
