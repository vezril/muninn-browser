# Tasks: e3-hardening-s2

## 1. Timer-throttling mitigation (host-timer-fidelity)

- [x] 1.1 Consult the `webkit-developer` agent for the correct macOS-26 mechanism — **DONE 2026-07-12; refuted the original design candidate.** Off-screen NSWindow is strictly dominated (needs SPI anyway, still App Naps, risks a stray window). Real mechanisms are process-level: RunningBoard suspension → `WKPreferences.inactiveSchedulingPolicy = .none` (**PUBLIC**, macOS 14+), and App Nap → `_setAppNapEnabled(false)` (**SPI**). Hidden-page DOM timer throttling is irrelevant (WorkerGlobalScope doesn't override `domTimerAlignmentInterval`). Design Decision 1 rewritten.
- [x] 1.2 Levers implemented — `HostThrottling.swift`: arm selector (`MUNINN_THROTTLE_ARM`, default B), dedicated `WKWebsiteDataStore` (process isolation, all arms), B=`inactiveSchedulingPolicy=.none` (public), C=`_setAppNapEnabled(false)` (SPI behind `allowsPrivateAPI`). Wired into `BackgroundHost.start()`; `webContentPID` accessor added.
- [x] 1.3 **Bisect measurement** (Decision 2): 4 arms × 120 s headless. **A=4 (FAIL, negative control ✓), B=125 (PASS), C=114, D=125.** The PUBLIC lever B alone clears the bar. RSS ~85 MB peak all arms (≤150 MB, no regression).
- [x] 1.4 No user-visible window (`testHostHasNoWindow` — host WebView `.window == nil`); process isolation (`testHostRunsInDedicatedProcess` — host pid ≠ independent WebView pid). PASS.
- [x] 1.5 `research/nfr10-residency-2026-07-12-post-mitigation.md` written. **No ADR-003 decision needed** — public lever suffices; `allowsPrivateAPI = false`, zero SPI in the shipping build.

## 2. Minimal fork.js injection (fork-bridge-isolation)

- [x] 2.1 `ForkBridgeInjector.swift` + `content-shim.js` — content shim in a named isolated `WKContentWorld` (`MuninnShim`, all frames, document-start); `fork.js` injected via nav-delegate only when `matchesForkHost` (pure, unit-tested); seam left for E5.
- [x] 2.2 Broker second context — `brokerIsolated` `WKScriptMessageHandlerWithReply` registered ONLY on the isolated world; relay routes to `MessageBroker.handle`. MAIN world gets no handler.

## 3. S2 verification (fork-bridge-isolation)

- [x] 3.1 MAIN-world isolation test — `testMainWorldIsIsolatedFromShim` (hermetic): MAIN-world `typeof window.chrome`/`window.browser` both `"undefined"`; isolated world exposes the shim. Plus `testBrokerHandlerNotReachableFromMainWorld` (broker handler undefined in MAIN world). PASS. (Fix: world-targeted value retrieval needs `callAsyncJavaScript`, not `evaluateJavaScript(_:in:in:)`.)
- [x] 3.2 Injection scoping — `testForkHostMatching` (pure): fork host-match true for account.proton.me + subdomains, false for example.com / look-alikes. Live-load scoping folded into the 3.3 observation.
- [x] 3.3 Fallback-selection — verified **by corollary**: `sendMessageSupported()` checks page-world `chrome.runtime` (research 2.1), which our verified MAIN-world isolation proves absent → the account app must take the postMessage fallback. The live *authenticated* observation is correctly E6's (ground rule 1). Reasoned in `research/s2-fork-fallback-2026-07-12.md`.
- [x] 3.4 Relay plumbing test — `testIsolatedRelayReachesBroker`: isolated-world `browser.runtime` storage round-trip reaches the native broker and returns; payload opaque. PASS.
- [x] 3.5 `research/s2-fork-fallback-2026-07-12.md` written: verified (isolation, scoping, relay, fallback-selection corollary) vs. deferred (authenticated handoff → E6). Verdict: **GO for E6**, carrying the dedicated-data-store cookie-sharing check.

## 4. Review & ship

- [ ] 4.1 XCTest suite covers §1 (no-window, process isolation) and §3 (isolation, scoping, fallback, relay); full suite green from a pristine clone
- [x] 4.2 Refute-oriented review — verdict MINOR-FIXES; **MAIN-world isolation confirmed airtight, tests non-vacuous.** Fixed: `matchesForkHost` exact-host + case-fold (was over-matching subdomains; test flipped), distinct `forkFailed` audit kind, content-shim main-frame-only, `ForkBridgeInjector.stop()`. Finding 2 (inbound native→content push unwired) documented as an E6/E5 carry in the S2 artifact (login uses postMessage fallback, not onMessageExternal, so out of S2 scope).
- [ ] 4.3 Ship via git-ship (PR-gated); update `CLAUDE.md` (E3-hardening + S2 done → E6 unblocked). Any run that would reach a login form stops for the E6 human gate (ground rule 1)
