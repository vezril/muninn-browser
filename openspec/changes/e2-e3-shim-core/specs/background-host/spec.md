# background-host

## ADDED Requirements

### Requirement: Vendored background.js boots clean (S1)
The hidden background host SHALL load the vendored bundle's `background.js` (with chunks and WASM served over the minimal extension-origin scheme loader) to a settled state with zero unhandled exceptions and zero unhandled `TypeError: browser.X.Y is not a function` in its console (FR-11 acceptance; Spike B risk 3 / S1).

#### Scenario: Boot log is clean
- **WHEN** the host loads `background.js` from the vendored v1.38.0 bundle and settles for 60 seconds
- **THEN** captured console/error output contains no unhandled exceptions or missing-API TypeErrors

#### Scenario: WASM crypto chunks load
- **WHEN** boot proceeds
- **THEN** `assets/wasm/*.wasm` requests are served with `application/wasm` and instantiate without error

### Requirement: Global-scope audit recorded
The boot SHALL produce a dated audit artifact (`research/sw-global-scope-audit-<date>.md`) listing every un-modeled API access captured by the polyfill's audit channel plus any `ServiceWorkerGlobalScope`-specific usage observed, each with a triage disposition; zero untriaged entries is the bar E8 re-checks (FR-7).

#### Scenario: Audit artifact exists and is triaged
- **WHEN** the S1 boot completes
- **THEN** the artifact exists, and every listed entry carries a disposition (stub added / benign-ignore / needs-fix-before-E6)

### Requirement: Host residency and isolation
The host SHALL remain alive with no suspend/wake cycle (process-level activity assertion per ADR-005), survive the crash of a sibling WKWebView, and be restarted by a watchdog on its own WebContent termination — with restart storms surfaced loudly rather than looped silently.

#### Scenario: Sibling crash isolation
- **WHEN** a sibling test WKWebView's content process is deliberately killed
- **THEN** the background host's context is unaffected (in-memory state intact, no reload)

#### Scenario: Watchdog restart
- **WHEN** the host's own WebContent process is deliberately killed
- **THEN** the watchdog reloads it, a restart event is logged, and `storage.local` state is intact post-restart

### Requirement: Resource ceiling measured
The host's steady-state footprint and timer fidelity SHALL be measured and recorded in the change: RSS after 30 minutes idle (NFR-10 target ≤150 MB) and JS timer drift over the same window (ADR-005's hidden-page throttling check). Measured-and-recorded here; binding re-verification is E11's.

#### Scenario: Idle measurement recorded
- **WHEN** the 30-minute idle run completes (one gated app launch, ground rule 2)
- **THEN** RSS and timer-drift figures are recorded in the change/tasks record, with NFR-10 conformance noted or the miss flagged
