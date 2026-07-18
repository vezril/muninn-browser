# Tasks: e6-auth-fork-login

> **CHECKPOINT (2026-07-12) — artifacts done, implementation not started.** Paused at Calvin's direction to take this pivotal go/no-go gate fresh. Two things surfaced at apply time and are now baked into `design.md` Decision 2: E6's core is a **cross-context request/response message bus** (page `runtime.sendMessage` → `background.js` `onMessage` in the host Worker, with `sendResponse` correlated back across two process boundaries; ~400–500 lines), materially bigger than the original "relay" framing — design revised. And the gate needs Calvin live (task 4.2). Resume by building group 1–3 (shell + bus + headless synthetic-context verification), then stop for the human login gate. Open architectural unknown: Decision 4 cookie/store topology (dedicated host store vs. shared) may force a trade with the timer fix.

## 1. Minimal shell (minimal-shell)

- [x] 1.1 `AppShell.swift` — real `.regular` app (headless/test paths preserved in `AppDelegate`): `NSWindow` + toolbar (back/forward/reload + address `NSTextField`) + the page `WKWebView` via Auto Layout; owns broker + host (started) + page.
- [x] 1.2 `ForkBridgeInjector` promoted to the shell's page context (builds the page WebView + isolated-world shim + fork.js scoping); shell holds it and registers the `page` broker context.
- [x] 1.3 Address-bar navigation (https:// prefixed if no scheme), back/forward/reload bound to the WebView; address field reflects the committed URL via KVO; nav path logs no URL content.

## 2. Cross-context request/response message bus (auth-fork-login) — the load-bearing new work (design Decision 2)

- [x] 2.1 Broker context registry — `MessageBroker`: named `host`/`page` contexts, `pushEvent(key,args,to:)` targets one (no broadcast); page delivery via `evaluateJavaScript(…, in: isolatedWorld)` → `__muninnContentPush`, host via `window.__shimPush`. `BackgroundHost`/`ForkBridgeInjector` register themselves.
- [x] 2.2 Async cross-context `sendMessage` — `routeSendMessageToHost`: correlation id → `runtime.onMessage` into the host worker `{message, sender, respId}` → parked `CheckedContinuation` (Sendable box for Swift 6) resolved by the worker's response; `handle()` stays synchronous for Tier-1.
- [x] 2.3 Worker polyfill — `fireMessage` passes a real `sendResponse` + honors `return true`=async-open; posts `{__shim:'response', id, result}` back through the host relay → `BackgroundHost` `resolveResponse`.
- [x] 2.4 Inbound native→content push wired (content-shim `__muninnContentPush`); sender identity `{id:canonical, url, frameId, tab}`. Primary login path is page→host+response (verified); host→page push is wired for E5/E6 events.
- [x] 2.5 Canonical identity — the bus test asserts the host-side `sender.id` is `ghmbeld…` (ADR-008).

## 3. Headless pre-gate verification

- [x] 3.1 XCTest: **full cross-context bus round-trip** (`E6MessageBusTests` — page `runtime.sendMessage` → host worker `onMessage` → `sendResponse` → back to page, sender=canonical id). PASS. This is the login path; only the *authenticated* half is unverified at the gate.
- [x] 3.2 Fork scoping + isolation in the page context covered by `ForkBridgeIsolationTests` (host-scoped injection, MAIN-world clean) + the bus test loading real pages; the shell reuses the same injector, so the guarantees carry.
- [x] 3.3 Full suite green (23 tests) after bus + shell. (Pristine-clone re-verify folded into ship.)

## 3b. externally_connectable MAIN-world bridge — the real E6 blocker fix (added 2026-07-17, design Decision 5)

> The E5 live gate (`research/e5-orchestrator-gate-2026-07-17.md`) re-diagnosed the "missing permissions" blocker: it is NOT orchestrator (that's injected and the bus works live), but the account app's presence-check running in the page **MAIN world via `externally_connectable`** (`chrome.runtime.sendMessage(extId)`), which S2 keeps empty. `background.js` reuses `onMessage` for `onMessageExternal.addListener`, and the worker shim already models `onMessageExternal` delivery — so the fix is a narrow MAIN-world bridge, not new host work.

- [x] 3b.1 `externally-connectable.js` — MAIN-world `chrome.runtime = {id, sendMessage, connect}`, **self-gated** to the manifest's `externally_connectable` hosts (interpolated); every other origin's MAIN world stays clean (S2). No native handle in MAIN — `sendMessage` bridges via `window.postMessage` to the isolated world.
- [x] 3b.2 Isolated relay (`content-polyfill.js`): a `window` `message` listener (double-gated on the frame's own blessed host + same-origin) routes `__muninnExt` → native `runtime.__externalMessage` → posts the response back to MAIN.
- [x] 3b.3 Native: `MessageBroker.routeExternalMessageToHost` pushes `runtime.onMessageExternal` with an EXTERNAL sender (`url`/`origin`/`tab`, no extension `id`); `IsolatedBridge` re-checks `frameInfo.securityOrigin.host` ∈ manifest hosts (defense-in-depth). `PassBundle.externallyConnectableHosts` derives the hosts from the manifest.
- [x] 3b.4 `E6ExternalConnectableTests` (3, green): MAIN-world `chrome.runtime.sendMessage(extId,…)` → `onMessageExternal` → response round-trip; narrow bridge shape on a blessed origin; MAIN stays clean on a non-blessed origin. Full suite 34 tests green.

## 4. The human gate (auth-fork-login — the Risk-1 go/no-go) — READY TO RE-ATTEMPT (bridge built)

- [x] 4.1 **[HUMAN GATE — ground rule 2]** Warned Calvin; launched the app (visible window) on his confirmation — twice.
- [~] 4.2 **[HUMAN GATE — ground rule 1]** Calvin at the keyboard, no credentials touched. **Progress:** fixed the fork trigger (`runtime.onInstalled` → `background.js` `tabs.create` → onboarding URL, now wired to the shell); the onboarding page loads with correct fork params. **Blocker:** the account app reports *"Proton Pass is missing permissions"* — the extension↔page permission handshake is unsatisfied. Pickup not yet observed.
- [x] 4.3 Findings recorded in `research/e6-auth-fork-2026-07-17.md`. **NOT D4** (engine/boot/injection/bus all work). Leading cause: we inject only `fork.js`, not `orchestrator.js` (the general content script the account app's detection depends on) → **E6 is coupled to E5 (general injection)**. Next: E5 `orchestrator.js` injection, then re-attempt the gate.

> **CHECKPOINT (2026-07-17):** Groups 1–3 done and green (shell + cross-context bus + isolation, 23 tests). Group 4 reached a precise, non-D4 blocker that needs E5's `orchestrator.js` injection. Recommend resequencing E5 before finishing E6, or a cheap experiment (inject orchestrator.js into the page isolated world and re-check the permission error).

> **CHECKPOINT (2026-07-17, post-E5):** E5 done. Built the externally_connectable MAIN-world bridge (group 3b, 37 tests green) and re-attempted the gate (4th live gate). **Bridge is confirmed installed live** (Web Inspector on account.proton.me MAIN world: `chrome.runtime.sendMessage` = function, `chrome.runtime.id` = canonical). But "missing permissions" persists: the account app's `onboarding.js` throws `t4.runtime` undefined (its webextension-polyfill fails to capture the API), and the manual round-trip couldn't be confirmed (inspector console context kept flipping frames). Full findings + 3 ranked hypotheses: `research/e6-external-gate-2026-07-17.md`. **Leading fix next: expose ONLY `window.chrome` (drop `window.browser`) to match real Chrome** — our `window.browser` likely sends Proton's polyfill down the Firefox branch and breaks it. Then add a programmatic gate signal (external message `type` + round-trip completion) instead of manual console probing. STILL NOT D4 — bridge installs and is correctly shaped live.

## 5. Review & ship

- [ ] 5.1 Refute-oriented review (MAIN-world isolation still airtight with a real navigable tab; no credential leak on any new path — address bar, relay, push; context-routing correctness)
- [ ] 5.2 Ship via git-ship (PR-gated); update `CLAUDE.md`. **If the gate passed: Risk 1 is retired — E4/E5/E7/E8 unblocked. If it failed: record D4 and pause the skeleton.**
