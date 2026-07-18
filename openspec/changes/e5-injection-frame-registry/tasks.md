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

- [x] 1.1 Inject `orchestrator.js` … relaunch the E6 gate flow and observe whether the account app's **"missing permissions"** clears. **DONE — live gate 2026-07-17** (`research/e5-orchestrator-gate-2026-07-17.md`). Result: orchestrator injects and the **cross-context bus works LIVE** (9 relay-in/response-out round trips from the real account.proton.me onboarding page), but **"missing permissions" persists**. Root cause sharpened: the account app's presence-check runs in the page **MAIN world via `externally_connectable`** (`chrome.runtime.sendMessage(extId)`), which S2 keeps empty. **Corrects the E6 checkpoint's stated blocker** — the real remaining gap is a narrow MAIN-world externally_connectable bridge → `onMessageExternal` (an E6 concern, not general injection)

## 2. Unify the isolated-world shim (design Decision 1)

- [x] 2.1 Refactor so the Proxy-catch-all polyfill runs in the content world with a content-world transport (`webkit.messageHandlers.brokerIsolated` for calls, `__muninnContentPush` inbound) — replacing the hand-written minimal `content-shim.js`; keep worker vs content transport behind a thin shim
- [x] 2.2 Ensure the polyfill user-script injects (isolated, `document_start`) BEFORE `orchestrator.js` (isolated, `document_end`) so `browser.*` exists when orchestrator runs

## 3. General injection (content-injection spec) — `InjectionCoordinator`

- [x] 3.1 `InjectionCoordinator` (renamed from `ForkBridgeInjector`): injects `orchestrator.js` (isolated, `document_end`, all frames) + `webauthn.js` (MAIN, `document_start`) via `WKUserScript`; `fork.js` nav-gated to `account.proton.me`. File `Muninn/Shim/InjectionCoordinator.swift`
- [x] 3.2 `AppShell` uses `InjectionCoordinator`; S2 isolation tests migrated to `InjectionCoordinatorIsolationTests` (all references renamed; 31 tests green)

## 4. orchestrator boot audit (content-injection spec)

- [x] 4.1 Headless harness (`OrchestratorBootAuditTests`): full injection set on a synthetic login page, host live, isolated-world `__audit` instrumentation + execution probes. Confirms the FR-9 set installs (5 scripts), the shim is present, MAIN stays clean, and the audit plumbing works
- [x] 4.2 `research/orchestrator-audit-2026-07-17.md` written. **Finding:** orchestrator does NOT complete boot in a *windowless* WKWebView (offscreen render/idle loop absent — page-side analogue of the E3 throttle); the **authoritative** boot evidence is the live gate (orchestrator boots clean, 9 bus round-trips, modelled shim only). No unmodelled-API gap identified — the real blocker is E6's externally_connectable bridge, not an orchestrator API
- [x] 4.3 **Ports decision (Decision 4b): DEFER.** Static scan: `orchestrator.js` initiates no ports; `background.js`'s 3 `onConnect` handlers serve other contexts (dropdown/notification iframes), not orchestrator boot. Cross-context ports stay off the E6 bus until a concrete flow needs them

## 5. Frame registry (frame-registry spec)

- [x] 5.1 `FrameRegistry` (`Muninn/Shim/FrameRegistry.swift`): main frame id 0 (parent -1), stable subframe ids keyed on `(isMainFrame, securityOrigin, url)` (WKFrameInfo has no public stable id on the 26.2 SDK). Backs `webNavigation.getAllFrames`/`getFrame` via `MessageBroker.webNavigationCall`; `resetSubframes()` on main-frame `didStartProvisionalNavigation`. Pure core (`resolve(isMain:url:originKey:parentId:)`) is unit-testable without a `WKFrameInfo`
- [x] 5.2 `runtime.getFrameId` resolves the caller's frame: the isolated bridge resolves `message.frameInfo` → id and answers `runtime.__resolveFrameId`; `content-polyfill.js` caches it on boot and `getFrameId()` returns it (Safari current-frame form; element-arg is post-MVP, Spike B risk #2)
- [x] 5.3 `FrameRegistryTests` (6, green): `getAllFrames` nested; `getFrame` by id + unknown→null; stable ids across re-resolve; reset keeps main; `getFrameId` main-frame → 0 end-to-end; srcdoc subframe gets a distinct positive id

## 6. Verify, review & ship

- [x] 6.1 XCTest: **S2 MAIN-world isolation still holds** with the full injection set — `OrchestratorBootAuditTests` asserts MAIN `chrome` is undefined under bootstrap+content-polyfill+orchestrator+webauthn; 4 `ForkBridgeIsolationTests` green. "orchestrator boots clean" is validated by the live gate (task 4 finding — headless boot is offscreen-limited)
- [x] 6.2 Full suite green: **30 XCTests, 0 failures** (`xcodebuild test -scheme Muninn`)
- [x] 6.3 Refute-oriented review (swiftui-reviewer) done — 4 findings, all fixed + re-verified: (1) reset moved to `didCommit` (a cancelled nav no longer wipes live subframes); (2) `getFrameId` uses `window.top===window` so a subframe returns -1 (pending), never a false 0; (3) identical-URL subframe collision documented + codified in a test; (4) dead `webNavigation` stub case removed. 31 tests green
- [x] 6.4 Shipped via gated PR #14 (branch `feat/e5-audit-frame-registry`); `CLAUDE.md` updated (E5 done → E6 needs the MAIN-world externally_connectable bridge). Merge is the human gate
