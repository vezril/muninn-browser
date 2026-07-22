# Tasks: documents-and-find

## Local files
- [x] `InjectionCoordinator.load` — `loadFileURL(_:allowingReadAccessTo:)` for file URLs.
- [x] `AppShell.fileURL` + `navigate(to:)` — recognize `/…`, `~/…`, `file://…`.
- [x] `MuninnWebView` file-drop (open in new tab), deferring non-file drags to WebKit; `onOpenFile` wiring.

## JSON viewer
- [x] `JSONViewer` script — detect JSON, prettify + colour + collapsible tree + toolbar; big-file `<pre>` fallback.
- [x] Inject at document-end (main frame); `AppSettings.formatJSON` toggle in Settings → General.
- [x] Verified renderer against a live application/json response (23 rows / 18 keys / 4 collapsible nodes).

## PDF download
- [x] `savePageAs` (⌘S / File menu / right-click "Download PDF") via tracked `startDownload`.
- [x] Native PDF HUD ⬇ wired via `_webView:saveDataToFile:…` private WKUIDelegate SPI (webkit-developer root-cause).
- [x] Shared `downloadsFolder()` / `uniqueDestination(for:in:)` helpers.

## Find in page
- [x] `FindBarView` (borderless field — fixed the nested-bezel double-box) + native `findString`.
- [x] Enter/⌘G next, ⇧⌘G prev, Esc close; JS "N matches" count; Edit-menu items.

## Ship
- [x] Build clean; full suite green (103); live-gated (files, JSON, PDF incl. HUD, find).
