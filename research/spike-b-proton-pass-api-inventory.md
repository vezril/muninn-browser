# Spike B — Proton Pass Extension: WebExtensions API Surface Inventory

**Question:** Is the `chrome.*`/`browser.*` API surface used by the Proton Pass extension small enough to implement as a purpose-built shim over WKWebView, making a WebKit-everywhere browser (Path 2) viable?

**Method:** Static analysis of Proton's open-source monorepo (`ProtonMail/WebClients`, `main` branch, shallow clone July 11 2026), scoped to `applications/pass-extension` and `packages/pass`. Grep-based enumeration of all `browser.<ns>.<method>` call sites, cross-referenced against the three shipped manifests (`manifest-chrome.json`, `manifest-firefox.json`, `manifest-safari.json`) and `BUILD_TARGET` conditionals in source.

**Verdict up front: GO — the hard column is short.** Proton already ships a WebKit-degraded build profile (`BUILD_TARGET === 'safari'`) that excludes every genuinely hard API. The shim spec is effectively *the Safari manifest*: ~10 namespaces, ~45 distinct methods/events, most of which map 1:1 onto WKWebView primitives. The real work is runtime plumbing, not API stubs.

---

## 1. The key discovery: the Safari build is the shim spec

Proton maintains three manifests. The deltas tell the whole story:

| Permission | Chrome | Firefox | **Safari (WebKit)** |
|---|---|---|---|
| `storage` / `unlimitedStorage` | ✔ | ✔ | ✔ |
| `alarms` | ✔ | ✔ | ✔ |
| `activeTab` / `scripting` | ✔ | ✔ | ✔ |
| `webNavigation` | ✔ | ✔ | ✔ |
| `nativeMessaging` | optional | optional | ✔ (required) |
| `clipboardWrite` | optional | optional | ✔ |
| **`webRequest`** | ✔ | ✔ (+blocking) | **✘ absent** |
| **`offscreen`** | ✔ | ✘ | **✘ absent** |
| `privacy` | optional | optional | ✘ absent |
| `commands` (keyboard shortcuts) | ✔ | ✔ | ✘ empty |

Source-level `BUILD_TARGET === 'safari'` guards confirm it: the Safari build skips the `webRequest`-based form-failure trackers, the Chrome-only offscreen clipboard document, dev-mode hot reload, and `browser.commands`. **Proton has already done the feature-triage for WebKit.** A custom shim only needs to reach parity with what their Safari build consumes — and autofill demonstrably works within that budget (validated empirically in Orion, whose coverage also lacks full `webRequest`).

## 2. Full API inventory (by call-site count, all builds)

### Tier 1 — Trivial over native primitives (~80% of call sites)

| Namespace | Methods/events used | WKWebView / AppKit mapping |
|---|---|---|
| `alarms` (47 calls) | `create`, `get`, `clear`, `clearAll`, `onAlarm` | `DispatchSourceTimer` registry. An afternoon. |
| `storage` (18) | `local.*`, `session.*` | File-backed JSON + in-memory dict. Keychain-wrap the local store for defense in depth. |
| `runtime` messaging (17) | `sendMessage`, `onMessage`, `connect`, `onConnect` (ports) | `WKScriptMessageHandler` (page→shim) + `evaluateJavaScript` (shim→page), with a small router. The single most important piece — everything flows through the message broker. |
| `runtime.getURL` (22) | — | `WKURLSchemeHandler` serving a custom scheme (e.g. `pass-ext://`) from the bundled extension resources. |
| `tabs` (36) | `query`, `get`, `getCurrent`, `create`, `remove`, `update`, `sendMessage`, `onUpdated`, `onRemoved` | You own the tab model — these become queries against your own `TabManager`. Easier than in a real browser. |
| `action` (9) | `setBadgeText`, `setBadgeBackgroundColor` | Your own toolbar UI. The popup is `popup.html` in an `NSPopover`-hosted WKWebView. |
| `windows` (4) | `create`, `update` | Your window manager. |
| `permissions` (11) | `request`, `contains`, `onAdded`, `onRemoved` | Stub: always granted. It's your browser. |
| misc `runtime` | `id`, `getManifest`, `lastError`, `reload` | Constants/stubs. |

### Tier 2 — Real engineering, but bounded

| Item | Why it matters | Approach |
|---|---|---|
| **Background service worker host** | `background.js` (MV3 service worker) must run somewhere with the shim injected | Hidden off-screen WKWebView (or JSContext) loaded via the custom scheme. Bonus: no MV3 suspend/wake semantics needed — keep it alive forever. Strictly *simpler* than Chrome's real lifecycle. |
| **Content-script isolation** | `orchestrator.js` runs in all frames at `document_end`; `webauthn.js` at `document_start` in **MAIN world** | `WKContentWorld` gives isolated worlds natively; `WKUserScript` supports injection time + `forMainFrameOnly` + world targeting, and `evaluateJavaScript(in:frame:contentWorld:)` covers `scripting.executeScript` (3 calls) and `insertCSS` (1). |
| **Injected UI iframes** | Autofill dropdown + save-login notification are iframes pointing at `dropdown.html` / `notification.html` (`web_accessible_resources`) | Served by the same `WKURLSchemeHandler`; must replicate web-accessible-resource semantics (allow embedding from any http(s) page, block everything else). |
| **`webNavigation.getFrame` / `getAllFrames`** (18) | Frame bookkeeping for cross-frame messaging | Maintain a frame registry from `WKNavigationDelegate` + `WKFrameInfo`. Fiddly but mechanical. |
| **`runtime.onMessageExternal`** (1 call, but critical path) | The **login flow**: `externally_connectable` from `*.proton.me` — the account web app messages the extension to complete the auth fork | Inject a tiny bridge content script only on `*.proton.me` that relays `postMessage` → shim. **This is the top validation risk — test the full login flow first.** |
| `clipboardWrite` | Copy password | `NSPasteboard`. Trivial, listed here only because Safari's build routes it differently than Chrome's offscreen hack. |
| WASM in extension pages | Crypto (`*.wasm` in web_accessible_resources) | WKWebView runs WASM fine; just serve correct MIME type from the scheme handler. |

### Tier 3 — Skippable (Safari build already excludes or optional)

| API | Usage | Disposition |
|---|---|---|
| `webRequest.*` (12 call sites) | Form-submission failure inference, XHR tracking, API proxy, `onAuthRequired` | **Skip.** Safari build ships without it. Degradation: slightly less clever "did this login fail?" heuristics. |
| `offscreen` | Chrome MV3 clipboard workaround | **Skip.** Chrome-only by design. |
| `privacy.services` (22 refs) | Disable Chrome's built-in password manager prompts | **Skip.** No competing password manager exists in your browser. |
| `nativeMessaging` (`connectNative`, `sendNativeMessage`) | Optional lock-state integration with the Proton Pass desktop app | **Defer.** Extension functions without it. Long-term you could implement it natively — your browser *is* a native app. |
| `commands` | Keyboard shortcuts | **Skip** (Safari build has none). Reimplement natively later if wanted. |
| `runtime.requestUpdateCheck` / `onUpdateAvailable`, `getBrowserInfo` | Update plumbing, Firefox version sniffing | Stubs. |

## 3. Scope estimate

- **API stubs (Tier 1):** ~45 methods/events across ~10 namespaces. Compare Orion's "hundreds of APIs over several years" — targeting one extension instead of 150,000 changes the problem class entirely.
- **Runtime plumbing (Tier 2):** the background host, scheme handler, content-world injection, frame registry, and message broker are ~4 subsystems. This is the actual project. Rough order: **4–8 focused weekends** for a walking skeleton (login → vault unlock → autofill on one site), assuming Swift + WKWebView.
- **Maintenance tail:** you re-validate the shim on each Proton Pass extension update. Their Safari build is your canary — if a new feature lands Safari-side, its API needs are by construction WebKit-compatible.

## 4. Top three risks to burn down first (ordered)

1. **Auth fork flow** (`onMessageExternal` bridge from `account.proton.me`) — if login can't complete, nothing else matters. First end-to-end test.
2. **Dropdown iframe mechanics** — custom-scheme iframe embedded in arbitrary pages, positioned by the content script; CSP interactions on strict sites.
3. **Service-worker global expectations** — `background.js` may assume `ServiceWorkerGlobalScope` APIs (`skipWaiting` is guarded to Chrome already, good sign); audit for others when the host is up.

## 5. Decision input

- **Path 2 (WKWebView everywhere + shim) is viable.** The hard column is short and Proton's own Safari build proves the degraded profile is acceptable — it's what you'd get in Safari anyway.
- **Path 1 (CEF/JCEF on Mac) remains the fast, boring baseline** — Spike A still worth its 1–2 evenings so the choice is made on data from both branches.
- The trade is now precise: **~a week to boring (Path 1)** vs. **~a couple of months to fully yours, one engine, symmetric sync, Safari-class battery (Path 2)** — plus a permanent but small maintenance duty tracking Proton Pass releases.

*Analysis based on ProtonMail/WebClients @ main, 2026-07-11. Re-run the grep inventory (5 min) before committing — Proton ships extension updates frequently.*
