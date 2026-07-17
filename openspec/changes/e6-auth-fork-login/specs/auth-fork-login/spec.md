# auth-fork-login

## ADDED Requirements

### Requirement: Bidirectional fork.js relay
The shim SHALL host Proton's `fork.js` in the tab's isolated content world on `account.proton.me`, relay the account app's `postMessage` handshake through the message broker to the background host, and deliver the background host's responses back into the page's isolated world (the inbound native→content push). Payloads are opaque throughout (FR-21).

#### Scenario: Inbound native→content push round-trip (headless, pre-gate)
- **WHEN** the broker pushes a synthetic event to the page's isolated-world context
- **THEN** the page's isolated world receives it via `__muninnContentPush` and a corresponding listener fires — verified headlessly before the login gate, so only the authenticated half is unverified at the gate

#### Scenario: Canonical identity presented
- **WHEN** `fork.js` / the account app reads the extension identity
- **THEN** `runtime.id` is the canonical production ID `ghmbeldphafepmbegfdlkpapadhbakde` (ADR-008)

### Requirement: Human-gated session pickup (the Risk-1 gate)
A manual login performed by Calvin at `account.proton.me` SHALL be picked up by the background host within 5 seconds, observed as a session-pickup event, with Muninn never requesting, reading, storing, or logging any credential (ground rule 1).

#### Scenario: Login is picked up
- **WHEN** Calvin (after the GUI-launch warning) logs in at `account.proton.me` himself
- **THEN** the background host observes a session-pickup event within 5 seconds under the canonical identity, and Calvin confirms the outcome verbatim; no credential-shaped data appears in any log or screenshot

#### Scenario: Failure escalates to D4
- **WHEN** pickup does not occur after reasonable debugging
- **THEN** the skeleton STOPS and the D4 fallback decision (fix-in-shim → pinned-tab Pass web app → CEF) is recorded — the failure is not papered over

### Requirement: Cookie/store topology verified
The change SHALL determine whether the background host (dedicated `WKWebsiteDataStore`, from E3-hardening) can act on the forked session without sharing the login tab's cookie store, and record the finding; if a shared store is required, the resulting tension with the timer-throttle process-isolation requirement SHALL be surfaced as a decision, not silently changed.

#### Scenario: Topology finding recorded
- **WHEN** the session pickup is exercised
- **THEN** the artifact records whether the dedicated-store host can service the session, and — if not — flags the store-topology-vs-timer-fidelity trade for Calvin
