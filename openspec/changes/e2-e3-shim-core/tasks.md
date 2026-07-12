# Tasks: e2-e3-shim-core

> **Session 1 progress note (2026-07-12).** Substrate correction ratified (Worker-inside-WKWebView; ADR-005 refined, design Decisions 1/4 amended). Core built, builds clean on Xcode 26.3 / Swift 6, and **verified headlessly** via an in-app diagnostic harness (`MUNINN_SHIM_DIAGNOSTIC` / `MUNINN_SHIM_SCENARIOS`, `.prohibited` activation → no window, within ground rule 2). **S1 is CLEAN** and all 6 core scenarios PASS. Two decisions parked for Calvin (see bottom).

## 1. Harness & plumbing

- [~] 1.1 Add the `MuninnTests` XCTest target — **DEFERRED, pending decision A.** Verification is currently execution-grounded via the headless diagnostic harness (real WKWebView + real background.js), not XCTest. Formal XCTest port needs objectVersion-77 test-target pbxproj surgery; flagged for Calvin rather than rushed.
- [x] 1.2 Minimal extension-origin scheme loader — `ExtensionSchemeHandler.swift` (`muninn-ext://<id>/…`, MIME incl. `application/wasm`, traversal-guarded, shim scripts from app bundle so they're same-origin with background.js). Not full FR-8/E4.

## 2. Tier-1 stubs + polyfill (E2)

- [x] 2.1 JS polyfill — `shim-polyfill.js` (Proxy catch-all per namespace; callback/promise duality + `lastError`; audit channel for unmodelled access; sync `getURL`/`id`/`getManifest`; installed into the worker only, never page MAIN world).
- [x] 2.2 Native stubs — `MessageBroker`/`AlarmRegistry`/`ExtensionStorage`: alarms (DispatchSourceTimer, **fire verified**), storage.local (AES-GCM + Keychain, **persist-across-restart verified**) + session, tabs/action/windows/permissions/scripting/webNavigation truthful minimums, clipboard via NSPasteboard, `nativeMessaging` benign no-op (**verified**).
- [~] 2.3 Verification — substance PASSes via the scenario harness (alarm fires, storage persists encrypted, nativeMessaging benign, unmodelled access audited-not-thrown). Formalize as XCTest under decision A.

## 3. Message broker (E2)

- [x] 3.1 Broker — `MessageBroker.swift` (envelope v1, `WKScriptMessageHandlerWithReply` async ingress, `evaluateJavaScript` push path, opaque payloads, audit sink). **Round-trip + event-push verified.**
- [x] 3.2 `onMessageExternal` inert event surface (polyfill eventHub; registers, never fires).
- [~] 3.3 Verification — round-trip ✓, payload-opacity ✓ (sentinel absent from all native logs). **Full port `connect`/`onConnect` + 50-message FIFO + disconnect DEFERRED to E6 (decision B):** they require a *second* live context (content script/page); with only the background host present there is no peer to exchange with. Broker plumbing is stubbed to reject `connect` cleanly meanwhile.

## 4. Background host (E3)

- [x] 4.1 `BackgroundHost.swift` — hidden WKWebView → DedicatedWorker running vendored `background.js`, console/error/rejection capture, process activity assertion, own configuration.
- [~] 4.2 Watchdog — implemented (`webViewWebContentProcessDidTerminate` → reload + logged restart, storm cutoff >3/10min → loud stop). **Not yet crash-tested** (see 4.5).
- [x] 4.3 **S1 spike — CLEAN.** Vendored v1.38.0 `background.js` boots in the Worker with zero errors, zero unhandled rejections, importScripts chunk loading + WASM resolving over the scheme. One benign audited access (`chrome.app` probe).
- [x] 4.4 Audit artifact — `research/sw-global-scope-audit-2026-07-12.md`, the single entry triaged Tier-3 benign; zero untriaged.
- [~] 4.5 Verification — boot-clean ✓, WASM loads ✓. **Sibling-crash isolation + watchdog-restart tests pending** (reliable WebContent-process kill in a headless harness is fiddly; do with decision A's test target).

## 5. Residency measurements (E3 / NFR-10)

- [ ] 5.1 **[HUMAN GATE — ground rule 2]** 30-min idle RSS + timer-drift measurement — pending; needs a gated launch window.

## 6. Review & ship

- [ ] 6.1 Pristine-clone end-to-end verify (build + verification suite).
- [ ] 6.2 Refute-oriented review pass (broker opacity, MAIN-world leak check, keychain handling).
- [ ] 6.3 Ship via git-ship; update `CLAUDE.md` state.

---

### Decisions parked for Calvin
- **A — Verification vehicle.** Accept the headless diagnostic harness as the execution-grounded verification for M1 (fast, real WKWebView + real background.js, no pbxproj risk) and formalize an XCTest target later? Or invest in the XCTest target now?
- **B — Port semantics scope.** `runtime.connect`/`onConnect` and the 50-message FIFO test genuinely need a second context, which arrives in E6. Defer that broker sub-task to E6 (recommended) rather than build a synthetic second context here?
