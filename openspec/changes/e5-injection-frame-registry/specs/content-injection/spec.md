# content-injection

## ADDED Requirements

### Requirement: Content scripts injected per the vendored manifest
The shim SHALL inject the vendored content scripts into the worlds, frames, injection times, and match patterns the manifest declares: `orchestrator.js` (isolated world, `document_end`, all frames, all `http(s)`), `webauthn.js` (MAIN world, `document_start`, all frames, all `http(s)`), and `fork.js` (isolated world, `document_end`, `account.proton.me` exact host). The isolated-world `browser.*` polyfill SHALL be injected before `orchestrator.js` runs.

#### Scenario: Orchestrator present on an ordinary page
- **WHEN** an arbitrary `https` page loads
- **THEN** `orchestrator.js`'s effects are present in the page's isolated world, and `webauthn.js` has run in the MAIN world

#### Scenario: Fork remains account-scoped
- **WHEN** a non-account page loads
- **THEN** `fork.js` is NOT injected (only `orchestrator.js` + `webauthn.js`), while on `account.proton.me` all three are present

### Requirement: orchestrator.js boots clean
`orchestrator.js` SHALL initialize in the isolated world with zero unhandled `TypeError: browser.X.Y is not a function`; any unmodelled API access SHALL be audited (not thrown) and triaged in a dated artifact (`research/orchestrator-audit-<date>.md`).

#### Scenario: Clean orchestrator init
- **WHEN** a page loads with the full injection set and orchestrator initializes
- **THEN** captured console/error output shows no unhandled exceptions or missing-API TypeErrors, and every audited access carries a Tier 1/2/3 disposition

### Requirement: MAIN-world isolation preserved (S2 carry)
Injecting the general content scripts SHALL NOT place the `browser.*`/`chrome.*` surface or the broker handler into the page MAIN world; `webauthn.js` (MAIN world) SHALL reference no `browser.*` API.

#### Scenario: MAIN world still clean with orchestrator present
- **WHEN** a page with the full injection set finishes loading and MAIN-world script evaluates `typeof window.chrome` / `window.browser` and the broker handler
- **THEN** all are `undefined` in the MAIN world, while the isolated world exposes the shim
