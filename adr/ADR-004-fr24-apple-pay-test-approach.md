# ADR-004 — FR-24 (Apple Pay Injection Suspension) Test Approach

**Status:** Accepted — Calvin Ference, 2026-07-11 22:55 EDT (architecture.md §10)
**Date:** 2026-07-11
**Source IDs:** FR-24, FR-9, E5, E10, E12
**Evidence:** PRD §6.6 FR-24 acceptance caveat; roadmap §5 (split flagged); `research/spike-b-proton-pass-api-inventory.md` (WKWebView niceties)

## Context

FR-24 requires the shim to tolerate WebKit disabling script injection on active pages (Apple Pay JS checkout flows) — no crash, frame registry intact, injection resuming on the next navigation. The PRD's own acceptance criterion carries a caveat: triggering WebKit's *real* suspension likely requires a live Apple Pay merchant session, which is an external dependency no test harness controls. The roadmap already split delivery (E10 fault-injection for M2; E12 live-session follow-up) and flagged the harness question to this phase.

## Decision

1. **M2 (E10) is satisfied by fault injection:** a debug hook in the InjectionCoordinator simulates the suspended state (injection calls fail / user scripts absent for the frame), and the test verifies graceful degradation — no crash, FrameRegistry consistent, automatic resume on next navigation. The injection-lifecycle abstraction in E5 SHALL model a `suspended/resumed` state from the start so the fault hook is a state override, not a bolted-on hack (architecture §4, InjectionCoordinator).
2. **M3 (E12) closes the loop against reality:** one manual session on a live Apple Pay merchant checkout (human-driven, no purchase completion required — reaching the Apple Pay sheet suffices to trigger the page state), observing that Pass UI degrades quietly and recovers after navigating away.
3. **No dedicated merchant-simulation harness is built.** The cost (Apple Pay JS requires a real merchant registration and domain validation) is grossly disproportionate to the risk for a solo project; fault injection covers the code path, the one live session covers the trigger.

## Consequences

- M2 does not block on an external dependency; FR-24's code path is still exercised deterministically and repeatably.
- Residual risk, accepted: the fault-injection model could mis-model how WebKit actually manifests the suspension (e.g., which calls fail, and how). The E12 live session is the check; if it falsifies the model, the fix lands as a bug against E5's abstraction, not an architecture change.
- The `suspended/resumed` state requirement is a design constraint handed to E5's stories now, avoiding a retrofit later.
