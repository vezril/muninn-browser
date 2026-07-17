# Proposal: e3-hardening-s2

## Why

Two things gate E6 (auth-fork login, the first go/no-go): a confirmed defect and an open spike, both flagged in `CLAUDE.md` and `architecture.md` §8.

1. **Timer throttling is real (E3 measurement).** `research/nfr10-residency-2026-07-12.md` confirmed WebKit throttles JS timers in the hidden background host (`setInterval(1000)` fired ~4× in 300 s). `chrome.alarms` is safe (native timer), but any `background.js` logic using raw `setTimeout`/`setInterval` — plausibly on the login/session path — would be starved. Must be fixed before E6 exercises the real login flow.
2. **S2 spike is open (gates E6).** ADR-007 / architecture §5a: verify the `fork.js` postMessage fallback path is actually selected inside Muninn's WKWebView (page world lacks `chrome.runtime`), and that nothing leaks `browserAPI`/`chrome` into a page's MAIN world (which would defeat the fallback detection and expose the API to hostile pages).

## What Changes

- **Background-host timer-throttling mitigation:** make the hidden host's WebKit page treat itself as "visible" so JS timers run at full fidelity — without showing a user-visible window (candidate: off-screen/occluded 1×1 `NSWindow` hosting the host WebView, or a WebKit throttling/visibility opt-out; the webkit-developer agent picks the exact mechanism). Re-measure timer fidelity to confirm.
- **Minimal content-world injection for S2 (not the full FR-9/E5 InjectionCoordinator):** inject Proton's `fork.js` on `*.proton.me` per the vendored manifest's match pattern, into an **isolated** `WKContentWorld`; wire the fork.js↔shim relay through the existing message broker as a second context.
- **S2 verification:** confirm (a) `window.chrome`/`window.browser` are **absent** in the page MAIN world on a loaded real page (no leak), (b) the isolated world has the shim API but the MAIN world does not, (c) on `account.proton.me` the page selects the postMessage fallback (chrome.runtime absent) and `fork.js` relays reach the background host. The **authenticated** end-to-end handoff stays E6 (human gate, ground rule 1) — this spike verifies plumbing + world isolation + fallback selection, not a real login.

## Capabilities

### New Capabilities
- `host-timer-fidelity`: the background host runs JS timers unthrottled (mitigation + re-measurement).
- `fork-bridge-isolation`: minimal isolated-world injection of `fork.js` on `*.proton.me` with verified MAIN-world non-leak and fallback-path selection (S2).

### Modified Capabilities

_None — the timer-fidelity guarantee is captured as the new `host-timer-fidelity` capability rather than a delta on the archived `background-host` spec (its residency requirement is unchanged; this adds the mitigation the E3 measurement showed necessary)._

## Impact

- **Files:** likely a small `HostWindow`/visibility helper + `InjectionCoordinator` (minimal), a MAIN-world isolation probe, new XCTests; possibly a tiny off-screen NSWindow owned by `BackgroundHost`.
- **Gates unblocked:** E6 (both its preconditions). E5 later generalizes the minimal injector into the full FR-9 frame registry.
- **Ground rules:** the off-screen window must be genuinely non-visible (ground rule 2 — no user-facing window). No credentials touched (ground rule 1); S2 stops at plumbing/selection, login is E6.
- **Deps/tools:** use the `claude-toolkit:webkit` skill + `webkit-developer` agent for the exact throttling/visibility mechanism and `swift-concurrency-expert` if window/actor interplay needs it.
