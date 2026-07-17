# host-timer-fidelity

## ADDED Requirements

### Requirement: Background-host JS timers run unthrottled
The background host SHALL run JS timers (`setTimeout`/`setInterval`) at approximately wall-clock fidelity while presenting **no user-visible window** — mitigating the WebKit hidden-page throttling confirmed at the E3 residency measurement. Target: ≥ 95% of expected ticks for a 1-second interval over a ≥ 60-second window.

#### Scenario: Timer fidelity restored
- **WHEN** the mitigated background host runs a `setInterval(1000)` in the worker for 300 seconds
- **THEN** it fires ≥ 285 times (≥95% of 300), versus the ~4 measured before mitigation

#### Scenario: No user-visible window
- **WHEN** the mitigation is active during normal app run
- **THEN** no window belonging to the background host is visible to or focusable by the user (ground rule 2), verified by window-list inspection

#### Scenario: Memory not regressed
- **WHEN** the mitigated host runs idle and RSS is sampled
- **THEN** the background host stays within NFR-10's ≤150 MB ceiling (no regression from the mitigation)

### Requirement: Mitigation is torn down cleanly
Any window or assertion introduced by the mitigation SHALL be released when the host stops (no leaked window, process-activity assertion, or occlusion state).

#### Scenario: Clean teardown
- **WHEN** `BackgroundHost.stop()` is called
- **THEN** any mitigation-owned window is closed and any assertion ended (no leak across a start/stop cycle)
