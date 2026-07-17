# NFR-10 residency — post-mitigation timer-fidelity bisect — 2026-07-12

Follow-up to `nfr10-residency-2026-07-12.md`, which confirmed the hidden background host's JS timers were throttled to ~4 ticks/300 s. The webkit-developer investigation traced this to two process-level mechanisms (RunningBoard suspension + App Nap), not DOM-timer throttling. This is the falsification bisect.

## Method

Headless (`MUNINN_SHIM_DIAGNOSTIC=1 MUNINN_SHIM_MEASURE=1`, `.prohibited` activation — no window, never key, no user input: the adversarial idle case). 4 arms × 120 s, a `setInterval(1000)` tick counter in the worker:

- **A** = default (negative control)
- **B** = `WKPreferences.inactiveSchedulingPolicy = .none` (**PUBLIC**, macOS 14+)
- **C** = `_setAppNapEnabled(false)` (**SPI**)
- **D** = both

All arms use a dedicated `WKWebsiteDataStore` (dedicated WebContent process — the throttle latch is per-process/one-way).

## Result

| Arm | Lever | JS timer ticks / 120 | Host RSS peak | Verdict |
|---|---|---|---|---|
| A | default | **4** | 87.5 MB | FAIL (negative control — reproduces the throttle ✓) |
| **B** | `.none` (public) | **125** | 84.9 MB | **PASS** |
| C | `_setAppNapEnabled(false)` (SPI) | 114 | 86.6 MB | PASS |
| D | both | 125 | 86.8 MB | PASS |

Target was ≥95% (≥114/120). Arm A's failure under conditions identical to the passing arms validates the negative control — the harness genuinely provokes the throttle.

## Decision — ship arm B (PUBLIC, zero private API)

**The public lever alone (`inactiveSchedulingPolicy = .none`) fully restores fidelity (125/120, ~104%).** The SPI App-Nap lever adds nothing over B (C alone is actually slightly lower). So:

- Shipping path = arm B only (the env default). `HostThrottling.allowsPrivateAPI = false` — **no SPI is invoked at runtime**. No ADR-003 distribution tension; no Calvin decision required.
- Precise MAS note: the SPI *selector literals* (`_setAppNapEnabled:`, `_webProcessIdentifier`) still compile into the binary (used by the bisect arms C/D and the process-isolation test). They are never called in arm B. For the current unsigned/personal build (ADR-003) this is fine; a future MAS build should compile them out (dev-only) to pass static analysis. Flagged for the OQ-5/1.0 revisit, not a blocker now.

## Memory (NFR-10 / NFR-3)

Host RSS peak ~85 MB across all arms — **well under NFR-10's 150 MB**, and the feared "un-suspended process isn't memory-compressed" rise did not materialize at this footprint (A's 87.5 MB ≈ B's 84.9 MB). No memory regression from the mitigation.

## Caveat carried forward

Window was 120 s (bisect economy); the earlier finding used 300 s. The binding 30-min soak remains E11's. The dedicated-data-store process isolation has an **E6 flag**: it changes cookie/storage sharing with `*.proton.me` tabs — verify the auth-fork handshake doesn't depend on a shared store.
