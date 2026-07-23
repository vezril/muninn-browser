# Proposal: e6-auth-fork-login

## Why

This is **roadmap E6 — the walking skeleton's Risk-1 gate and the project's first true go/no-go** (PRD §9, Spike B risk 1). Everything downstream (E4/E5/E7/E8) is untestable until a real login at `account.proton.me` is picked up by the shim: *"if login can't complete, nothing else matters."* The shim core (E2/E3) and both E6 preconditions (E3-hardening timer fix + S2 isolation spike) are landed; the remaining piece is a minimal navigable shell plus the bidirectional auth-fork wiring, exercised by Calvin at a human gate.

## What Changes

- **Minimal shell (FR-1, FR-4, FR-5):** one `NSWindow` with one navigable tab (a page `WKWebView`), an address field, and back/forward/reload — *just enough* to reach `account.proton.me` and, later, a target site. Not the FR-2/3 tab model (E9); one tab only.
- **Auth-fork wiring (FR-13):** host `fork.js` on `account.proton.me` in the tab's isolated world (from the S2 injector, now in a real tab), relay the account app's `postMessage` handshake through the broker to the background host, and — the S2 carry — **wire the inbound native→content push** so the background host's replies reach the page's isolated world, completing the handshake bidirectionally. Present the canonical extension identity (ADR-008).
- **Human-gated login validation:** warn before the GUI launch (ground rule 2); Calvin performs the login himself (ground rule 1); observe the background host receive a session-pickup event within 5 s under the canonical ID. Muninn never sees credentials.
- **E6 carry-downs verified:** confirm the dedicated background-host `WKWebsiteDataStore` (from E3-hardening) does not break the handshake's cookie/session assumptions.
- **D4 fallback on failure:** if pickup fails, STOP and escalate the D4 ladder (fix-in-shim → Pass web app pinned tab → CEF), recorded — do not paper over it.

## Capabilities

### New Capabilities
- `minimal-shell`: a single window + one navigable tab + address/nav controls (FR-1, FR-4, FR-5).
- `auth-fork-login`: the bidirectional fork.js relay and human-gated session pickup at the background host under the canonical ID (FR-13), incl. the inbound native→content push the S2 review flagged.

### Modified Capabilities

_None — `fork-bridge-isolation` stays as archived; the inbound-push wiring is captured under the new `auth-fork-login` capability rather than a delta on the archived spec._

## Impact

- **Files:** a real `AppShell`/window + tab controller (replacing the diagnostic-only entry), address/nav UI, broker inbound-push wiring to the page context, the ForkBridgeInjector promoted from spike object to the tab's page context.
- **Ground rules front and center:** GUI-launch warning before any window; login performed only by Calvin; no credential capture in logs/screenshots. This is the first change that is fundamentally a **human-gated interactive test** — the authenticated pickup cannot be verified headlessly.
- **Gate semantics:** success unblocks E4/E5/E7/E8; failure triggers D4 and pauses the skeleton.
- **Tools:** the `claude-toolkit:webkit` skill / `webkit-developer` agent for navigation-delegate and cross-context messaging details.
