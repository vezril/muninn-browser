# Tasks: browser-extensions

- [x] Bump deployment target 15.0 → 15.4 (WKWebExtension availability)
- [x] `ExtensionManager` — shared `WKWebExtensionController`, async load/unload, auto-grant
      permissions + `allRequestedMatchPatterns`, install from folder/.zip/.crx, persist `index.json`
- [x] `ExtensionBridge` — `WKWebExtensionControllerDelegate` + `ExtTab`/`ExtWindow` proxies over
      `BrowserTab`/window; `openNewTab` + `presentActionPopup`
- [x] `ExtensionHost` protocol on AppShell (tabs/window/open/activate/close/present)
- [x] `InjectionCoordinator` conditionally attaches the controller (gated on `hasEnabledExtensions`)
      to preserve S2 clean MAIN world
- [x] Action toolbar row under the address field; click → popup (transient) / click event
- [x] Tab open/close/activate notifications to keep extensions in sync
- [x] Settings → **Extensions** section (Add…, enable/disable switch, remove w/ confirm)
- [x] Bundled test extension `tools/sample-extension` (content script + popup + background)
- [x] Live gate: content script, toolbar popup, external popup script, MV3 CSP — all verified
- [x] 81 XCTests green (S2 clean-world test preserved)
- [x] Version bump → v0.20.0
