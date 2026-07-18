# Design: e5-injection-frame-registry

## Context

E6 proved the shim boots Proton's `background.js`, drives the fork, and round-trips the message bus — but the account app's onboarding rejects with "missing permissions" because only `fork.js` is injected. The manifest declares three content scripts; we inject one. E5 delivers the general injection (FR-9) + frame registry (FR-9, `runtime.getFrameId`), which should clear the wall. `orchestrator.js` is 94 KB minified and wraps its `browser.*` access behind an alias (like `background.js`), so its exact API needs can't be grepped — the reliable method is the S1 approach: give it a Proxy catch-all shim, boot it, and audit what it touches.

## Goals / Non-Goals

**Goals:**
- Inject per the vendored manifest: `orchestrator.js` (isolated world, `document_end`, all frames, all `http(s)`), `webauthn.js` (MAIN world, `document_start`, all frames), `fork.js` (isolated, `account.proton.me`).
- `orchestrator.js` boots with zero unhandled `TypeError`s (S1-style), auditing any unmodelled API for triage.
- Frame registry answers `webNavigation.getFrame`/`getAllFrames` and `runtime.getFrameId` from `WKFrameInfo`/`WKNavigationDelegate`.
- S2 isolation preserved: the `browser.*`/`chrome.*` surface stays out of the page MAIN world; `webauthn.js` (MAIN) is Proton's own script and must use no `browser.*`.

**Non-Goals:**
- The E6 login gate re-attempt (does "missing permissions" clear end-to-end) — that's **E6's** completion, run live with Calvin; E5 verifies orchestrator boots clean + injection/registry correctness (plus a cheap early experiment).
- Autofill dropdown / field icon (`orchestrator.js`'s UI features) beyond "boots clean" — **E7**.
- The full popup/vault-unlock (FR-14) — E7.

## Decisions

1. **Unify the shim polyfill across worker and content world.** The worker uses `shim-polyfill.js` (Proxy catch-all + audit + transport = `postMessage` to the host page). The content world currently uses a hand-written minimal `content-shim.js` — too small for `orchestrator.js`. Refactor so the **same Proxy-catch-all polyfill** runs in the content world with a **content-world transport** (`webkit.messageHandlers.brokerIsolated` for calls; `__muninnContentPush` for inbound). This gives `orchestrator.js` the full `browser.*` surface and audits unmodelled access — the robust, empirical path. Keep the worker/content transport differences behind a tiny shim-of-the-shim.
2. **Injection via `WKUserScript` for the always-on scripts.** `orchestrator.js` and `webauthn.js` match all `http(s)` pages, so they inject via `WKUserScript` (no per-nav gating): orchestrator → `.atDocumentEnd`, isolated world, `forMainFrameOnly:false`; webauthn → `.atDocumentStart`, **`.page` (MAIN) world**, `forMainFrameOnly:false`. `fork.js` stays nav-delegate-gated to `account.proton.me` (exact host). Order: the polyfill user-script must inject before orchestrator (document_start, isolated) so `browser.*` exists when orchestrator runs at document_end.
3. **Frame registry from `WKFrameInfo`.** Track frames via `WKNavigationDelegate` (`decidePolicyFor`/`didCommit`) and the `WKFrameInfo` on script messages (each `WKScriptMessage.frameInfo`). Assign stable integer frame ids (0 = main frame per Chrome convention). `webNavigation.getFrame`/`getAllFrames` and `runtime.getFrameId` read this. `runtime.getFrameId` for a content-script call resolves via the calling message's `frameInfo`.
4. **Empirical boot + audit for orchestrator (mirrors S1).** Add a headless harness that loads a test page with the full injection set, boots `orchestrator.js`, and captures its audit log + errors. Iterate the shim surface until clean. Write `research/orchestrator-audit-<date>.md`, triaging any unmodelled API (Tier 1/2/3) — this is also an FR-25-style surface check for the content-script side.
4b. **Ports, if needed (empirical).** E2/E3 deferred `runtime.connect`/`onConnect`. If the orchestrator boot audit shows port usage, implement cross-context ports on the same bus as E6's `sendMessage` (correlation + the `port` message kinds already stubbed in the worker polyfill). If not, leave deferred. Decide from the audit, don't pre-build.
5. **S2 isolation re-verified with the fuller surface.** With orchestrator + the full isolated-world polyfill, re-assert MAIN-world cleanliness (no `chrome`/`browser`, no `brokerIsolated`) — the E5 injector must not regress S2. `webauthn.js` in MAIN world is Proton's code; verify it references no `browser.*` (Chrome MAIN-world content scripts get no extension APIs, so it must not).
6. **`InjectionCoordinator` subsumes `ForkBridgeInjector`.** The E6 seam becomes the general coordinator; `AppShell` uses it. `fork.js` scoping + the S2 tests carry over.

## Risks / Trade-offs

- [orchestrator.js needs a large/surprising API surface] → the audit bounds it; expand the shim to cover, or triage Tier-3 skips. Same discipline as S1.
- [webauthn.js in MAIN world violates S2 or misbehaves] → verify no `browser.*`; if it needs an extension bridge (it shouldn't in MAIN world), that's a finding to surface, not silently paper over.
- [Frame-id semantics vs Chrome] → `getFrameId` is used once by orchestrator; a correct main=0 + per-subframe id from `WKFrameInfo` should suffice; verify against orchestrator's use.
- [orchestrator boots clean but the E6 "missing permissions" still doesn't clear] → then the detection mechanism is something else (a specific `permissions`/probe path); the cheap experiment (task 1) catches this early before full E5 investment.
- [Injecting into all frames widens the broker-reachable surface] → isolation still holds (page MAIN world can't reach it); audit cross-origin subframe behavior; deny-by-default posture where classification is unclear.

## Migration Plan

Additive refactor; `ForkBridgeInjector` → `InjectionCoordinator` (tests migrate). Rollback = revert. No persisted-state change.

## Open Questions

- Whether the "missing permissions" clears with orchestrator alone — answered by the task-1 cheap experiment before committing to the full frame registry.
- Whether ports are needed — answered by the orchestrator boot audit (Decision 4b).
