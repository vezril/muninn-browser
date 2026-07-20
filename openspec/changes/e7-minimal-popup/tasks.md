# Tasks: e7-minimal-popup

## 1. PopupHost — render popup.html with the shim

- [x] 1.1 `PopupHost`: a `WKWebView` loading `muninn-ext://<id>/popup.html`. Inject bootstrap (id+manifest) + the shim (`content-polyfill` Proxy) into the **MAIN world** (trusted extension page) at `document_start`; register a `brokerPopup` message handler + the `popup` broker context. Reuse `ExtensionSchemeHandler`.
- [x] 1.2 Headless test: `popup.html` loads (`didFinish`), and `window.chrome.runtime`/`browser.storage` are present in the popup's MAIN world.

## 2. Wire the popup to the broker + background

- [ ] 2.1 Popup `runtime.sendMessage` → `background.js` `onMessage` (reuse `routeSendMessageToHost` with a `popup` sender) and responses back. `storage.*` shares the broker's `ExtensionStorage` (so `storage.session["f"+state]` round-trips to background's consume).
- [ ] 2.2 `tabs.create`/`windows.create`/`window.location` for the fork URL drive the shell tab (reuse `broker.onOpenURL`).
- [x] 2.3 **Cross-context ports — DONE.** popup/page `runtime.connect(id,{name})` → real port to the host worker's `onConnect`; bidirectional `postMessage`, `onMessage`/`onDisconnect`; keyed port registry in `MessageBroker` (`portConnect`/`portMessageFromClient`/`portMessageFromHost`/`portDisconnect`); worker `shim-polyfill` builds the port on inbound `connect`; relays via `background-host-page.js` + `BackgroundHost`. `CrossContextPortTests` green (round-trip both ways).

## 3. Present the popup

- [ ] 3.1 Show the popup in a window/panel from `AppShell` (a toolbar button or auto-open for the gate) so the user can click "Sign in". Warn Calvin before launching (ground rule 2).

## 4. Gate: complete the auth-fork login

- [ ] 4.1 **[HUMAN GATE — ground rules 1+2]** Calvin opens the popup, clicks "Sign in", logs in. Expect: popup fork-init writes `f<state>` → account login → `fork` message → consume finds `f<state>` → `pullFork` via the fetch proxy → **login completes** (vault-locked state reached). Gate log stays type/host/status only.
- [ ] 4.2 Record the result; if login completes, **Risk 1 is retired**.

## 5. Verify, review & ship

- [ ] 5.1 Refute review (MAIN-world shim only on the trusted popup origin, not web pages; no credential capture; broker context routing; port opacity if added).
- [ ] 5.2 Full suite green.
- [ ] 5.3 Ship PR-gated; update `CLAUDE.md` + E6/E7 checkpoints. If login completed, mark Risk 1 retired and finish/ship the coupled changes (e6-auth-fork-login, native-fetch-proxy).

## Gate finding (2026-07-20) — popup boots but awaits background state

With cross-context ports live, the popup no longer errors — its React app BOOTS:
`document.body` = 173KB HTML, main `app-root` is 600×430 and styled (3 stylesheets,
`<style id="pass-theme">` injected). But the app tree is otherwise EMPTY (no login
form) — the popup is waiting for **background.js's initial state** (its auth-service
`init` / the popup↔background boot protocol) before rendering the login UI, and never
receives it. No JS errors.

**Next — two paths:**
- **(a) Deep popup integration:** diagnose what background.js's `auth.init` / state
  handshake needs (i18n.getMessage, crypto worker, a specific message the popup sends
  that background doesn't answer) so the popup renders the login screen. The "right"
  path; potentially several subsystems. NOTE: Proton's Safari profile EXCLUDES
  `offscreen` (CLAUDE.md) — so crypto likely runs in a Worker/chunk, not an offscreen doc.
- **(b) Minimal fork-init shim (retire Risk 1 faster):** invoke the extension's
  `requestFork` directly (store `storage.session["f"+state]` + open the fork URL) to
  prove the auth-fork LOGIN end-to-end without the full popup UI. Bypasses the popup
  render; validates the hardest risk while the full popup (E7) is built separately.
