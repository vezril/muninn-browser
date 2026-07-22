# Proposal: documents-and-find

Four related fixes/features around opening and reading documents locally, plus in-page search.

## 1. Open local files

Muninn couldn't open local files at all. Two root causes fixed:
- **Load path:** `InjectionCoordinator.load` used `webView.load(URLRequest)`, which WKWebView **silently
  refuses** for `file://`. Now file URLs go through `loadFileURL(_:allowingReadAccessTo:)`, granting the
  enclosing directory so a local page's sibling assets (css/js/images) load too.
- **Address bar:** `navigate(to:)` mangled `/Users/…/x.json` into `https:///…`. Now `AppShell.fileURL`
  recognizes `/…`, `~/…`, and `file://…` and loads them as files.
- **Drag & drop:** `MuninnWebView` now intercepts **file** drops (→ open in a new tab), while deferring
  image/text/upload drags to WebKit so page drop-zones and drag-to-upload still work.

## 2. Built-in JSON viewer (Firefox-style)

`JSONViewer` (MAIN-world, document-end) replaces a raw JSON document with a **prettified, syntax-coloured,
collapsible tree** + a toolbar (Pretty/Raw, Expand/Collapse all, Copy). Self-gates on
`document.contentType` (json) or a `.json` URL **and** a successful `JSON.parse`, so it never touches HTML
pages; `*.proton.me` untouched. URL string values become links; files > ~3 MB fall back to a highlighted
`<pre>` for responsiveness. Toggle in **Settings → General → "Format & colour JSON documents"** (default on).

## 3. Download the PDF you're viewing

WebKit renders PDFs inline (`canShowMIMEType` → never a `WKDownload`), so there was no way to save one.
Added three routes, all through the tracked download path (profile folder + Library):
- **⌘S** / **File → Save Page As…** / **right-click → Download PDF** (`AppShell.savePageAs` + a
  `MuninnWebView` context-menu item).
- **The native PDF HUD ⬇ button now works.** It was a silent no-op because WebKit fetches the bytes then
  early-outs when the `uiDelegate` doesn't implement a private "save data" callback. Implementing
  `_webView:saveDataToFile:suggestedFilename:mimeType:originatingURL:` (private `WKUIDelegatePrivate` SPI,
  macOS 10.13.4+) plugs the bytes into the same save+record path. **Lowest-risk SPI in the app** — we only
  *implement* a callback WebKit may invoke; no private symbol is called or linked (root-caused from WebKit
  source via the webkit-developer agent).

## 4. Find in page (⌘F)

`FindBarView` — a floating bar (magnifier + borderless field + prev/next + count + close) over the web
card, driving WKWebView's native `findString(_:withConfiguration:)` for highlight/scroll. Enter/⌘G next,
⇧⌘G previous, Esc closes and clears. A JS-computed **"N matches"** readout compensates for WebKit's find
API exposing no count. Works on any page and inside the JSON viewer. Under **Edit → Find… / Find Next /
Find Previous**.

## Impact

New: `Muninn/JSONViewer.swift`, `Muninn/FindBarView.swift`. Edits: `InjectionCoordinator` (file load, JSON
injection, `onOpenFile`, HUD save callback, shared download-destination helpers), `MuninnWebView` (file
drop + Save-Page/Download-PDF menu item + `onOpenFile`), `AppShell` (file-aware navigate, `savePageAs`,
find bar, `onOpenFile` wiring), `AppDelegate` (Save Page As, Find/Next/Prev menu items), `SearchEngine`
(`AppSettings.formatJSON`), `SettingsWindowController` (JSON toggle). 103 XCTests green; JSON renderer
verified against a live `application/json` response; live-gated.
