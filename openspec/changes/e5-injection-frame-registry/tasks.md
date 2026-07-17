# Tasks: e5-injection-frame-registry

> **CHECKPOINT (2026-07-17):** Core content-world injection is built and green
> (23 XCTests). The isolated-world Proxy polyfill (`content-polyfill.js`) is
> unified with a content-world transport; orchestrator.js + webauthn.js are
> injected with correct worlds/timing; S2 MAIN-world isolation still holds under
> the bigger surface (4 ForkBridgeIsolationTests green); the E6 cross-context bus
> passes (root-caused a regression: the polyfill's Proxy fallback rejected
> `runtime.sendMessage` instead of routing it to native — now fixed).
> **Remaining (fresh session):** task 1 (live "missing permissions" gate — needs
> a GUI launch under ground rules 1+2), task 4 (orchestrator boot audit), task 5
> (frame registry + `runtime.getFrameId`), and the rest of task 6. `ForkBridgeInjector`
> is not yet renamed to `InjectionCoordinator` but carries the full injection set.

## 1. Cheap experiment first (de-risk before full build)

- [ ] 1.1 Inject `orchestrator.js` into the page isolated world (alongside a fuller polyfill) the same way `fork.js` is injected; relaunch the E6 gate flow and observe whether the account app's **"missing permissions"** clears (or advances). Record the result — this confirms/refutes the orchestrator hypothesis before the full frame-registry investment (ground rules 1+2 if it reaches a login) — _[injection built + green headlessly; live gate deferred to fresh session]_

## 2. Unify the isolated-world shim (design Decision 1)

- [x] 2.1 Refactor so the Proxy-catch-all polyfill runs in the content world with a content-world transport (`webkit.messageHandlers.brokerIsolated` for calls, `__muninnContentPush` inbound) — replacing the hand-written minimal `content-shim.js`; keep worker vs content transport behind a thin shim
- [x] 2.2 Ensure the polyfill user-script injects (isolated, `document_start`) BEFORE `orchestrator.js` (isolated, `document_end`) so `browser.*` exists when orchestrator runs

## 3. General injection (content-injection spec) — `InjectionCoordinator`

- [~] 3.1 `InjectionCoordinator` (subsumes `ForkBridgeInjector`): `orchestrator.js` (isolated, `document_end`, all frames, all http(s)) + `webauthn.js` (MAIN, `document_start`, all frames) via `WKUserScript`; `fork.js` nav-gated to `account.proton.me` — _[full injection set wired into `ForkBridgeInjector`; formal rename deferred]_
- [ ] 3.2 `AppShell` uses the coordinator; migrate the S2 isolation tests

## 4. orchestrator boot audit (content-injection spec)

- [ ] 4.1 Headless harness: load a test page with the full injection set, boot `orchestrator.js`, capture its audit log + errors
- [ ] 4.2 Iterate the shim surface until `orchestrator.js` boots with zero unhandled TypeErrors; write `research/orchestrator-audit-<date>.md` triaging every unmodelled API (Tier 1/2/3)
- [ ] 4.3 **Ports decision (Decision 4b):** if the audit shows `runtime.connect`/`onConnect`, implement cross-context ports on the E6 bus; else leave deferred and note

## 5. Frame registry (frame-registry spec)

- [ ] 5.1 `FrameRegistry` from `WKNavigationDelegate` + `WKFrameInfo`: main frame id 0, stable subframe ids; back `webNavigation.getFrame`/`getAllFrames`
- [ ] 5.2 `runtime.getFrameId` resolves the calling `WKScriptMessage.frameInfo` to a frame id
- [ ] 5.3 XCTests: `getAllFrames` on a nested-iframe page; `getFrame` by id (+ unknown→null); `getFrameId` from main vs subframe

## 6. Verify, review & ship

- [~] 6.1 XCTest: orchestrator boots clean; **S2 MAIN-world isolation still holds** with the full injection set (no `chrome`/`browser`/broker handler in MAIN world; `webauthn.js` uses no `browser.*`) — _[isolation half proven: 4 ForkBridgeIsolationTests green with orchestrator+webauthn injected; "orchestrator boots clean" is the task-4 audit]_
- [ ] 6.2 Full suite green from a pristine clone
- [ ] 6.3 Refute-oriented review (MAIN-world leak with the bigger surface; frame-id correctness; port opacity if added; injection ordering)
- [ ] 6.4 Ship via git-ship (PR-gated); update `CLAUDE.md` (E5 done → re-attempt the E6 login gate next). If the task-1 experiment already cleared "missing permissions," note the E6 gate is ready to finish
