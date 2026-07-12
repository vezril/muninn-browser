# Tasks: e2-e3-shim-core

> **Session 1 progress note (2026-07-12).** Substrate correction ratified (Worker-inside-WKWebView; ADR-005 refined, design Decisions 1/4 amended). Core built, builds clean on Xcode 26.3 / Swift 6, and **verified headlessly** via an in-app diagnostic harness (`MUNINN_SHIM_DIAGNOSTIC` / `MUNINN_SHIM_SCENARIOS`, `.prohibited` activation → no window, within ground rule 2). **S1 is CLEAN** and all 6 core scenarios PASS. Two decisions parked for Calvin (see bottom).

## 1. Harness & plumbing

- [x] 1.1 `MuninnTests` XCTest target added (decision A) — host-based, app window suppressed under `XCTestConfigurationFilePath`, shared `Muninn.xcscheme` with a TestAction. **16 tests green via headless `xcodebuild test`** (ShimUnitTests + BackgroundHostIntegrationTests). The diagnostic harness remains as a fast iteration aid.
- [x] 1.2 Minimal extension-origin scheme loader — `ExtensionSchemeHandler.swift` (`muninn-ext://<id>/…`, MIME incl. `application/wasm`, traversal-guarded, shim scripts from app bundle so they're same-origin with background.js). Not full FR-8/E4.

## 2. Tier-1 stubs + polyfill (E2)

- [x] 2.1 JS polyfill — `shim-polyfill.js` (Proxy catch-all per namespace; callback/promise duality + `lastError`; audit channel for unmodelled access; sync `getURL`/`id`/`getManifest`; installed into the worker only, never page MAIN world).
- [x] 2.2 Native stubs — `MessageBroker`/`AlarmRegistry`/`ExtensionStorage`: alarms (DispatchSourceTimer, **fire verified**), storage.local (AES-GCM + Keychain, **persist-across-restart verified**) + session, tabs/action/windows/permissions/scripting/webNavigation truthful minimums, clipboard via NSPasteboard, `nativeMessaging` benign no-op (**verified**).
- [x] 2.3 Verification — XCTest cases in `ShimUnitTests`: storage get/set/remove/clear + defaults + session-resets-local-persists + at-rest-encrypted; alarm fires + clear; broker storage round-trip, truthful minimums, nativeMessaging-benign-but-rejects, unmodelled-audited-not-silent, payload-opacity. All green.

## 3. Message broker (E2)

- [x] 3.1 Broker — `MessageBroker.swift` (envelope v1, `WKScriptMessageHandlerWithReply` async ingress, `evaluateJavaScript` push path, opaque payloads, audit sink). **Round-trip + event-push verified.**
- [x] 3.2 `onMessageExternal` inert event surface (polyfill eventHub; registers, never fires).
- [x] 3.3 Verification — round-trip (native + worker→native integration), dead-recipient path, payload-opacity all covered by XCTest. **Full port `connect`/`onConnect` + 50-message FIFO + disconnect DEFERRED to E6 (decision B):** they require a *second* live context; broker rejects `connect` cleanly meanwhile.

## 4. Background host (E3)

- [x] 4.1 `BackgroundHost.swift` — hidden WKWebView → DedicatedWorker running vendored `background.js`, console/error/rejection capture, process activity assertion, own configuration.
- [x] 4.2 Watchdog — implemented + **crash-tested**: `testWatchdogRestartsAfterWebContentCrash` kills the real WebContent PID (SIGKILL) → watchdog reloads → background.js re-boots → `storage.local` survives. Storm cutoff coded.
- [x] 4.3 **S1 spike — CLEAN.** Vendored v1.38.0 `background.js` boots in the Worker with zero errors, zero unhandled rejections, importScripts chunk loading + WASM resolving over the scheme. One benign audited access (`chrome.app` probe).
- [x] 4.4 Audit artifact — `research/sw-global-scope-audit-2026-07-12.md`, the single entry triaged Tier-3 benign; zero untriaged.
- [x] 4.5 Verification — `testBackgroundJsBootsClean` (S1, only benign chrome.app audited), `testWorkerToNativeStorageRoundTrip`, `testUnmodelledApiRejectsInWorkerWithoutThrowing`, `testSiblingCrashDoesNotAffectHost` (real sibling WebContent kill leaves host untouched), plus the watchdog test (4.2). WASM chunk loading covered by boot-clean.

## 5. Residency measurements (E3 / NFR-10)

- [x] 5.1 Residency measurement — ran headlessly (no GUI, no gate needed): `research/nfr10-residency-2026-07-12.md`. **Memory PASS** (host peak 68 MB vs NFR-10's 150; total 237 MB vs NFR-3's 400). **⚠️ Finding: hidden-page JS timer throttling confirmed** (worker `setInterval` fired 4× in 300 s) — ADR-005 risk 7 is real. Primary periodic path (`chrome.alarms` → native timer) is unaffected; raw JS `setTimeout`/`setInterval` in background.js would throttle. Mitigation scoped as **E3-hardening before E6's login validation** (off-screen/occluded window or WebKit throttling opt-out — needs a spike). Window shortened to 300 s; binding 30-min run is E11's.

## 6. Review & ship

- [x] 6.1 Pristine-clone verify — fresh clone of the branch: `xcodebuild` BUILD SUCCEEDED + all 16 tests green (TEST SUCCEEDED). Self-contained.
- [x] 6.2 Refute-oriented review pass — reviewer verdict BLOCKERS; **all 6 real findings fixed**: (1) credential blocker — Proton `log/info/debug` console text no longer captured (only warn/error), test markers moved to a separate `__report` channel; (2) activity-assertion leak on watchdog restart (guard `activity == nil`); (3) Swift-6 timer-handler isolation (`MainActor.assumeIsolated`); (4) `runtime.connect` synchronous inert Port stub (was a rejecting Promise → TypeError risk); (5) path-traversal sibling-prefix boundary; (6) Keychain `SecItemAdd` duplicate handling; plus `storage.onChanged` now fires and root-Proxy `then` guard. MAIN-world leak + broker payload opacity reviewed **clean**. Re-verified: scenarios PASS, S1 CLEAN, build green.
- [ ] 6.3 Ship via git-ship; update `CLAUDE.md` state.

---

### Decisions (Calvin, 2026-07-12)
- **A — Verification vehicle: Add XCTest now.** Build the `MuninnTests` target this change and port the harness scenarios to real XCTest cases before shipping. The diagnostic harness stays as a fast iteration aid.
- **B — Port semantics: Defer to E6.** `runtime.connect`/`onConnect` + 50-message FIFO need a real second context (first exists in E6); build+verify them there. This change ships with `connect` cleanly rejecting. The message-broker spec's port scenarios are correspondingly out of scope for this change (noted in its spec).
