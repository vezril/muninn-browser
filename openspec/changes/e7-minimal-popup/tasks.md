# Tasks: e7-minimal-popup

## 1. PopupHost — render popup.html with the shim

- [x] 1.1 `PopupHost`: a `WKWebView` loading `muninn-ext://<id>/popup.html`. Inject bootstrap (id+manifest) + the shim (`content-polyfill` Proxy) into the **MAIN world** (trusted extension page) at `document_start`; register a `brokerPopup` message handler + the `popup` broker context. Reuse `ExtensionSchemeHandler`.
- [x] 1.2 Headless test: `popup.html` loads (`didFinish`), and `window.chrome.runtime`/`browser.storage` are present in the popup's MAIN world.

## 2. Wire the popup to the broker + background

- [ ] 2.1 Popup `runtime.sendMessage` → `background.js` `onMessage` (reuse `routeSendMessageToHost` with a `popup` sender) and responses back. `storage.*` shares the broker's `ExtensionStorage` (so `storage.session["f"+state]` round-trips to background's consume).
- [ ] 2.2 `tabs.create`/`windows.create`/`window.location` for the fork URL drive the shell tab (reuse `broker.onOpenURL`).
- [ ] 2.3 **Ports — CONFIRMED REQUIRED (gate 2026-07-20):** the popup renders BLANK because `popup.js` does `runtime.connect(id,{name})` and drives its UI over the port (`port.onMessage`/`onDisconnect`/`postMessage`); `background.js` `onConnect` stores the port + broadcasts state. Our inert port stub delivers nothing → blank. **Implement minimal cross-context ports (popup↔native↔host worker):** real portId, bidirectional `postMessage`, `onMessage`/`onDisconnect` delivery, keyed port registry in the broker. This is the last piece before the popup renders + Sign in works.

## 3. Present the popup

- [ ] 3.1 Show the popup in a window/panel from `AppShell` (a toolbar button or auto-open for the gate) so the user can click "Sign in". Warn Calvin before launching (ground rule 2).

## 4. Gate: complete the auth-fork login

- [ ] 4.1 **[HUMAN GATE — ground rules 1+2]** Calvin opens the popup, clicks "Sign in", logs in. Expect: popup fork-init writes `f<state>` → account login → `fork` message → consume finds `f<state>` → `pullFork` via the fetch proxy → **login completes** (vault-locked state reached). Gate log stays type/host/status only.
- [ ] 4.2 Record the result; if login completes, **Risk 1 is retired**.

## 5. Verify, review & ship

- [ ] 5.1 Refute review (MAIN-world shim only on the trusted popup origin, not web pages; no credential capture; broker context routing; port opacity if added).
- [ ] 5.2 Full suite green.
- [ ] 5.3 Ship PR-gated; update `CLAUDE.md` + E6/E7 checkpoints. If login completed, mark Risk 1 retired and finish/ship the coupled changes (e6-auth-fork-login, native-fetch-proxy).
