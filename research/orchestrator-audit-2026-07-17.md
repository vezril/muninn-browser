# orchestrator.js boot audit — E5 task 4

**Date:** 2026-07-17
**Harness:** `MuninnTests/OrchestratorBootAuditTests.testOrchestratorInjectionAndAuditPlumbing`
**Bundle:** vendored Pass v1.38.0 (`vendor/pass-extension/1.38.0/`)

## Goal

S1 was the *background.js* boot audit (worker substrate). This is its content-side
counterpart: audit what `browser.*` surface `orchestrator.js` (the general content
script, isolated world, `document_end`, all frames) needs, so gaps can be modelled and
orchestrator boots clean — and decide whether cross-context **ports** are required
(Decision 4b).

## Method

Headless harness: background host live, full FR-9 injection set on a synthetic login
page (`https://example.com/login` via `loadHTMLString`). Test-only instrumentation
(isolated world, `document_start`, after content-polyfill) reports through the same
`__audit` channel: unhandled `error`/`unhandledrejection`, and **execution probes**
wrapping the modelled calls orchestrator would hit on boot (`runtime.sendMessage`,
`runtime.getURL`, `storage.local.get`) plus `runtime.connect`/`onConnect` (ports). The
harness also routes `requestIdleCallback`→`setTimeout` and sets
`inactiveSchedulingPolicy = .none` to fight offscreen throttling.

## Findings

### 1. The FR-9 injection set installs correctly

5 user scripts registered (bootstrap → content-polyfill → orchestrator.js →
webauthn.js + instrumentation); `orchestrator.js` loads (94,789 bytes); the isolated
world exposes the shim; the page MAIN world stays clean (S2 holds under the full set);
the `__audit` plumbing delivers records. All asserted green.

### 2. Orchestrator does NOT complete its boot in a windowless WKWebView

No execution probe fires, no DOM is injected (`document.body.children` stays at the
original form; `outerHTML` unchanged), and no error reaches the isolated `error`
handler. Orchestrator's boot entry runs `o()` synchronously at `document_end`
(`readyState === "interactive"` passes its guard), but the actual work does not proceed.

Root cause: an **offscreen web content process has no render/idle loop**, and
orchestrator defers real work accordingly. Routing `requestIdleCallback`→`setTimeout`
and disabling RunningBoard suspension were **not sufficient** — this is the page-side
analogue of the E3 offscreen-throttling problem, and a fully headless boot would need an
on-screen window (ground rule 2 forbids surprise GUI windows in automated runs). A
synchronous throw inside the isolated world is also not observable via the isolated
`error` event (a WKWebView content-world quirk), so "boots clean" cannot be *proven*
headlessly either way.

### 3. Authoritative boot evidence is the live gate

`research/e5-orchestrator-gate-2026-07-17.md`: on the **real, visible** onboarding page,
orchestrator boots and runs cleanly — **9 cross-context bus round-trips**, onboarding UI
rendered, no crash — with the **current modelled shim**. No unmodelled-API failure
surfaced. So the practical answer to "does orchestrator boot on our shim?" is **yes**,
established live; the headless harness is a plumbing/injection regression guard, not the
boot oracle.

### 4. Decision 4b — cross-context ports: DEFER

Static scan: `orchestrator.js` initiates **no** ports (no `runtime.connect`, no
`onConnect`, no `postMessage`). `background.js` registers 3 `onConnect` handlers, but
those serve other contexts (the dropdown / notification WAR iframes, and possibly
fork.js), **not** orchestrator boot. The live gate carried the whole handshake over
`runtime.sendMessage`/`sendResponse` (the E6 bus) with zero ports. **Cross-context
ports stay deferred** off the E6 bus until a concrete flow (dropdown autofill, or a
port-based account handshake) demonstrably needs them.

## Unmodelled-API surface

Empty in the headless run (orchestrator reached no `browser.*` before its boot stalled;
the only audit record is the harness's own `__harness.instrumentation [loaded]`). The
live gate exercised only **modelled** calls (all 9 round-trips succeeded), so no Tier-1/2/3
gap is currently identified. The true remaining blocker is not an orchestrator API gap
but the **MAIN-world `externally_connectable` bridge** (see the gate finding) — an E6
concern.

## Verdict

- Orchestrator injection: correct; boots clean live on the modelled shim.
- Headless full-boot: environment-limited (offscreen render/idle loop); harness kept as
  an injection + audit-plumbing regression guard.
- Ports: **deferred** (4b) — orchestrator needs none.
- No shim surface change required by this audit; E6's externally_connectable bridge is
  the next real work.
