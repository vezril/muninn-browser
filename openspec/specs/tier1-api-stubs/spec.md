# tier1-api-stubs Specification

## Purpose
TBD - created by archiving change e2-e3-shim-core. Update Purpose after archive.
## Requirements
### Requirement: Tier-1 surface does not throw
The shim SHALL expose `browser.*`/`chrome.*` polyfills for the Tier-1 namespaces (`alarms`, `storage`, `tabs`, `action`, `windows`, `permissions`, `scripting`, misc `runtime`) plus `nativeMessaging` no-ops (FR-12, ratified skeleton scope) such that Pass code touching any member of the FR-25-validated surface never hits `TypeError: browser.X.Y is not a function`; access to members *outside* the validated surface returns a logged, rejected call rather than throwing at property access.

#### Scenario: Validated surface is callable
- **WHEN** each namespace.member in `tools/regrep-baseline.txt` (Tier 1/2 dispositions, minus E5's frame registry and E4+ members) is invoked with plausible arguments in a test context
- **THEN** none throws a TypeError; each returns a well-formed result or rejection

#### Scenario: Unstubbed access is audited, not fatal
- **WHEN** code accesses `browser.someNamespace.someUnknownMember`
- **THEN** the call is logged to the audit channel with namespace, member, and stack, and returns a rejected promise

### Requirement: Behavioral minimum for stateful stubs
`alarms` SHALL schedule and fire real timers through the broker event path; `storage.local` SHALL persist across host restart (keychain-wrapped at-rest per NFR-8); `storage.session` SHALL survive within a run and reset across runs; `tabs`/`action`/`windows` SHALL return truthful minimum shapes (no tabs exist yet).

#### Scenario: Alarm fires
- **WHEN** `alarms.create("t", {delayInMinutes: 0.01})` is called in the background context
- **THEN** `onAlarm` fires with the alarm object within a tolerance window

#### Scenario: storage.local persists across restart
- **WHEN** a value is written via `storage.local.set`, the host is terminated and restarted, and `storage.local.get` runs
- **THEN** the value is returned intact, and the at-rest file is not plaintext-readable

#### Scenario: nativeMessaging no-op is benign
- **WHEN** `runtime.connectNative()` or `runtime.sendNativeMessage()` is called at boot
- **THEN** no crash or unhandled rejection propagates (FR-12 acceptance)

