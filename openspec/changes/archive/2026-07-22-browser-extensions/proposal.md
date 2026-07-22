# Proposal: browser-extensions

Add the ability to **install and run browser extensions**, built on Apple's official
**`WKWebExtension` / `WKWebExtensionController`** API (macOS 15.4+). This reverses the original
"no general extension platform" constraint — Apple shipped a first-party Web Extensions runtime for
WKWebView apps, so we adopt it rather than hand-rolling one.

Deployment target bumped **15.0 → 15.4** to use the API (Calvin is on macOS 26).

## Install

Settings gains an **Extensions** section:

- **Add Extension…** — an open panel accepting an **unpacked folder** (containing `manifest.json`)
  *or* a packed **.zip / .crx**. Archives are unpacked with `/usr/bin/unzip` (which reads the
  trailing central directory, so it handles both `.zip` and `.crx`); if the manifest is nested one
  level down, that subfolder is used. The result is copied into
  `~/Library/Application Support/Muninn/Extensions/<id>/`.
- **Per-extension enable / disable** (a switch) and **remove** (deletes the unpacked files).
- The installed list is persisted to `Extensions/index.json`.

## Engine

- **`ExtensionManager`** (`@MainActor` singleton) wraps a shared `WKWebExtensionController`
  (`.default()`). It loads each enabled extension asynchronously
  (`WKWebExtension(resourceBaseURL:)` → `WKWebExtensionContext` → `controller.load`), auto-granting
  the extension's requested permissions and **all requested match patterns** (via
  `allRequestedMatchPatterns`, so declared content scripts get host access and inject).
- **`ExtensionBridge`** is the `WKWebExtensionControllerDelegate` and vends stable
  `WKWebExtensionTab` / `WKWebExtensionWindow` proxies over Muninn's real `BrowserTab`s and window,
  so `tabs.query`/`tabs.create`, activate/close/reload, and tab events reflect the real browser.
  AppShell conforms to an `ExtensionHost` protocol supplying tabs/window/open/activate/close.
- **Action toolbar** — a thin row under the address field with one button per loaded extension's
  action; clicking presents its **popup** (`WKWebExtensionAction.popupPopover`, transient) or fires
  the click event for popup-less actions. Rebuilt when the active tab changes or an extension
  loads/unloads.

## S2 interaction (Pass shim clean-world)

Attaching a `WKWebExtensionController` to a web view injects a `browser` global into that page's
**MAIN world**, which would violate the Pass shim's S2 clean-world invariant. So the controller is
**only attached to a tab's configuration when at least one extension is enabled**
(`ExtensionManager.hasEnabledExtensions`). With zero extensions installed, behaviour is byte-for-byte
unchanged and the existing S2 test stays green. Once the user opts into extensions, `browser` may
appear in the MAIN world — the accepted trade-off of supporting extensions. (Consequence: a freshly
installed extension applies to **new tabs**; already-open tabs pick it up on relaunch, since a
`WKWebViewConfiguration` is fixed at creation.)

## Compatibility & scope

- Compatibility follows Apple's WebExtensions support (MV3-leaning, the Safari subset) — not every
  Chrome extension will load. No Chrome Web Store integration (CRX download/update is out of scope).
- MVP auto-grants permissions (no per-permission prompt UI).
- **App Store caveat**: none — `WKWebExtension` is public API (unlike the Developer-Mode inspector's
  private symbols).

## Validation

Validated live (consistent with the WKWebView-integration work): the bundled test extension
`tools/sample-extension` (banner content script + toolbar popup + background worker) loaded and ran
end to end — content script injected, toolbar action opened its popup, the popup's external script
ran, and MV3 CSP correctly blocked an inline-script variant. All 81 existing XCTests remain green.

## Impact

New `Muninn/Extensions/` (`ExtensionManager`, `ExtensionBridge` + tab/window proxies); Settings
**Extensions** section; `InjectionCoordinator` conditionally attaches the controller; AppShell hosts
the bridge, the action toolbar, and tab open/close/activate notifications. Deployment target 15.4.
