# Design: e3-hardening-s2

## Context

The background host is a hidden WKWebView created `frame: .zero`, never added to a window → WebKit treats its page as non-visible and throttles JS timers (measured: ~4 ticks/300 s). The message broker (ADR-007) already supports multiple contexts logically; so far only the host exists. S2 needs a *second* context — a real web page with `fork.js` injected — to verify world isolation and fallback selection. Constraints: no user-visible window (ground rule 2); no credentials/login (ground rule 1 — login is E6); the exact WebKit throttling knob is version-sensitive, so pin it empirically with the webkit-developer agent rather than guessing.

## Goals / Non-Goals

**Goals:**
- Background-host JS timer fidelity ≥ ~95% of wall-clock (e.g. ≥285 ticks/300 s for a 1 s interval) while the host has **no user-visible window**.
- `fork.js` injected on `*.proton.me` in an isolated `WKContentWorld`; relay reaches the broker as a second context.
- Proven MAIN-world isolation: on a loaded page, `window.chrome`/`window.browser` are undefined in MAIN world; the shim API exists only in the isolated world.
- Fallback-path selection confirmed on `account.proton.me` (page MAIN world has no `chrome.runtime`, so the account app takes the postMessage path).

**Non-Goals:**
- Full FR-9 InjectionCoordinator + frame registry / `runtime.getFrameId` (E5).
- Authenticated login / session handoff (E6, human gate).
- Full port semantics (E6).
- `orchestrator.js`/autofill injection, dropdown (E5/E7).

## Decisions

1. **Timer mitigation — mechanism RESOLVED by the webkit-developer investigation (2026-07-12), and it refutes this design's original candidate.** Findings, traced to WebKit source + verified against the macOS 26.2 SDK on this machine:
   - **My assumed mechanism was wrong.** WebCore's hidden-page *DOM timer* throttling cannot affect our timers: `WorkerGlobalScope` does **not** override `ScriptExecutionContext::domTimerAlignmentInterval()` — only `Document` applies page throttling. Our `setInterval` lives in a DedicatedWorker.
   - **The two real mechanisms, both process-level:** (1) **RunningBoard suspension** (UI-process side) — every WebContent process launches holding a "BG Lifetime Activity"; `WKPreferences.inactiveSchedulingPolicy` defaults to `.suspend` for apps linked against the macOS 14+ SDK (we are), which drops it. (2) **App Nap** (content-process side) — `WebPage::isThrottleable()` = `m_isAppNapEnabled && !isActive && isVisuallyIdle`; when true the process drops `NSActivityLatencyCritical`, which is exactly the flag that disables kernel timer coalescing.
   - **Off-screen NSWindow (original candidate a) is REJECTED — strictly dominated.** It would still need SPI (`_setWindowOcclusionDetectionEnabled`, since an off-screen/alpha-0 window reports occluded), and *even then* `isVisuallyIdle` is true app-wide whenever window modifications stop and no window is key → `isThrottleable()` stays true → App Nap anyway. It adds a window, risks violating ground rule 2, and doesn't fix the problem.
   - **Chosen levers, public-first:** **Lever B** = `WKPreferences.inactiveSchedulingPolicy = .none` (**PUBLIC**, macOS 14+) — the sanctioned fix, header prose describes our exact case. **Lever C** = `_setAppNapEnabled(false)` (**SPI**) — only if B alone misses the bar. Best outcome: B suffices and we ship **zero private API**. Also add `ProcessInfo.beginActivity(.latencyCritical)` on the UI process (**public**) so the `chrome.alarms` `DispatchSourceTimer`s don't coalesce when Muninn isn't frontmost.
   - **Process-isolation prerequisite (already satisfied):** the throttling latch is **per-process and one-way** — any co-resident page on the default policy re-throttles the host forever. Our dedicated `WKWebsiteDataStore` guarantees a dedicated WebContent process. **⚠️ Flag for E6:** a dedicated store changes cookie/storage sharing with `*.proton.me` tabs — verify the auth-fork handshake doesn't depend on shared cookies.
   - **Memory tension to watch:** an unsuspended process is not memory-compressed, so host RSS will be **higher** than the throttled baseline — real tension with NFR-10's 150 MB.

2. **Falsification — bisect, with a negative control (identify the mechanism, don't just chase the symptom).** Run 4 arms × 300 s: **A** default, **B** `.none` only, **C** SPI only, **D** both. Arm A must **fail** (~4 ticks) under conditions identical to a passing arm, or the harness isn't provoking the throttle and the run is discarded. Our existing harness already satisfies the adversarial conditions — it runs `.prohibited` (no window ever, never key, no user input) and *did* produce the failing baseline of 4 ticks/300 s, so the negative control is real. Ship the **least-privileged arm that clears the bar** (prefer B → zero SPI).

3. **Minimal injector, not E5's coordinator.** A small `ForkBridgeInjector` adds one `WKUserScript` (fork.js) to an isolated content world, scoped to `*.proton.me` via navigation-delegate URL checks (WKUserScript can't match-pattern by itself). Deliberately narrow — E5 replaces it with the general FR-9 injection + frame registry. Keep the seam so E5 can subsume it.

4. **Second broker context = the page.** The page WebView registers a `WKScriptMessageHandlerWithReply` in the **isolated** world only; `fork.js` (and the shim polyfill it needs) run there. The MAIN world gets nothing. This is the structural guarantee against leak (ADR-007) — verified, not assumed.

5. **S2 verification is a spike artifact.** Results (world-isolation pass, fallback-selection observation, surprises) recorded in `research/s2-fork-fallback-<date>.md` with an E6 go/no-go. Where the authenticated step can't be reached without login, record exactly what was and wasn't verified (honest partial spike).

6. **Reuse the headless diagnostic pattern.** Isolation checks and fidelity re-measurement run headlessly (`.prohibited`, no window) and as XCTests, same as e2-e3. Loading `account.proton.me` is a plain network page load (no login) — allowed; any run that would reach a login form stops for the E6 human gate.

## Risks / Trade-offs

- [Lever B (public) alone doesn't clear ≥95%] → bisect tells us; falling back to the SPI (`_setAppNapEnabled`) buys fidelity at a distribution cost — gate it behind an `allowsPrivateAPI` flag so an MAS build can be produced without it, and flag the ADR-003 tension to Calvin rather than deciding unilaterally.
- [Neither lever clears the bar without a visible window] → record the finding honestly and escalate; the architecture may have to push periodic work onto native `chrome.alarms` (which already works) rather than ship a fake fix.
- [Un-suspended process is not memory-compressed → host RSS rises] → real tension with NFR-10's 150 MB; re-measure memory in the same run, and if it breaches, surface the fidelity-vs-footprint trade rather than silently busting the budget.
- [Per-process, one-way throttling latch] → a co-resident page on the default policy would re-throttle the host permanently. Our dedicated `WKWebsiteDataStore` forces process isolation; assert host-pid ≠ tab-pid in test. **⚠️ E6 flag:** the dedicated store also changes cookie/storage sharing with `*.proton.me` tabs — verify the auth-fork handshake doesn't depend on a shared store.
- [Injecting fork.js changes page trust] → it's Proton's own vendored code; isolated world only, `*.proton.me` only, MAIN world clean (the whole point of S2).
- [S2 can't verify the authenticated handoff here] → scope to plumbing + isolation + fallback selection; E6 owns the gated login. Don't overclaim.

## Migration Plan

Additive; rollback = revert. No window is created (the rejected approach would have needed one), so nothing window-shaped can leak; ensure the UI-process activity assertion is ended in `BackgroundHost.stop()` (the e2-e3 review lesson).

## Open Questions

- Which arm clears the bar (B alone vs. needing the SPI) — answered by the Decision-2 bisect during apply. If the SPI is required, that becomes a Calvin decision (ADR-003 distribution tension), not an implementer's call.
