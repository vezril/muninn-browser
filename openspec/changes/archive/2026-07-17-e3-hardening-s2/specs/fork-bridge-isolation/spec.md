# fork-bridge-isolation

## ADDED Requirements

### Requirement: fork.js injected only in an isolated world on *.proton.me
Muninn SHALL inject the vendored `fork.js` into an **isolated** `WKContentWorld` on pages matching the vendored manifest's `fork.js` content-script pattern (`https://account.proton.me/*`), and SHALL NOT inject it on other origins. The shim API the bridge needs SHALL exist only in that isolated world.

#### Scenario: Injected on proton.me, absent elsewhere
- **WHEN** a page at `https://account.proton.me/…` loads, and separately a page at `https://example.com/` loads
- **THEN** `fork.js`'s effects are present in the isolated world on the proton.me page and absent on example.com

### Requirement: No shim/browser API leaks into the page MAIN world (S2)
On any loaded page, `window.chrome` and `window.browser` SHALL be undefined in the **MAIN** world, and `webkit.messageHandlers` for the broker SHALL NOT be reachable from page scripts — so the account app selects the `postMessage` fallback and hostile pages cannot reach the shim (ADR-007).

#### Scenario: MAIN world is clean
- **WHEN** a real page finishes loading and MAIN-world script evaluates `typeof window.chrome` / `typeof window.browser`
- **THEN** both are `"undefined"`, while the isolated world does expose the shim API

#### Scenario: Fallback path is selected on account.proton.me
- **WHEN** `account.proton.me` loads in Muninn (no login performed)
- **THEN** the account app's environment detection finds `chrome.runtime` absent in the page world and takes the `postMessage` fallback path (the path `fork.js` relays) — observed via the message channel, not by completing auth

### Requirement: fork.js relay reaches the background host
The `fork.js`→shim relay SHALL route through the message broker to the background host as a distinct second context (plumbing verification; the authenticated session handoff is E6).

#### Scenario: Relay plumbing works
- **WHEN** a synthetic relay message is emitted from the isolated world on a proton.me page
- **THEN** it is delivered through the broker to the background host, and a reply returns — with payloads treated opaquely (FR-21)

> **Scope note:** the real, authenticated login handoff (account.proton.me session → extension) is **E6**, performed by Calvin at a human gate (ground rule 1). This spike verifies world isolation, fallback selection, and relay plumbing only. Results recorded in `research/s2-fork-fallback-<date>.md` with an E6 go/no-go.
