# Tasks: e6-auth-fork-login

> **CHECKPOINT (2026-07-12) — artifacts done, implementation not started.** Paused at Calvin's direction to take this pivotal go/no-go gate fresh. Two things surfaced at apply time and are now baked into `design.md` Decision 2: E6's core is a **cross-context request/response message bus** (page `runtime.sendMessage` → `background.js` `onMessage` in the host Worker, with `sendResponse` correlated back across two process boundaries; ~400–500 lines), materially bigger than the original "relay" framing — design revised. And the gate needs Calvin live (task 4.2). Resume by building group 1–3 (shell + bus + headless synthetic-context verification), then stop for the human login gate. Open architectural unknown: Decision 4 cookie/store topology (dedicated host store vs. shared) may force a trade with the timer fix.

## 1. Minimal shell (minimal-shell)

- [ ] 1.1 Build `AppShell`: real `.regular` app path (keep the `MUNINN_SHIM_DIAGNOSTIC` headless paths) — `NSWindow` + a `WebTab` hosting a page `WKWebView`, address `NSTextField`, back/forward/reload toolbar bound to the WebView
- [ ] 1.2 Promote `ForkBridgeInjector` from spike object to the tab's page context (it builds the page WebView + isolated-world shim + fork.js scoping); the shell owns it
- [ ] 1.3 Address-bar navigation + nav controls; address field reflects the committed URL; no credential/URL-content logging on the nav path

## 2. Cross-context request/response message bus (auth-fork-login) — the load-bearing new work (design Decision 2)

- [ ] 2.1 Broker context registry: named contexts (`host`, `page`) each with a native→JS push delivery + origin tag; `pushEvent(key,args,to:)` targets one context (no broadcast); page delivery via `evaluateJavaScript(…, in: isolatedWorld)` → `__muninnContentPush`
- [ ] 2.2 Async cross-context `sendMessage`: page-origin `runtime.sendMessage` → correlation id → `runtime.onMessage` into the host worker `{message, sender, __respId}` → parked continuation resolved by the worker's response; keep synchronous `handle()` for Tier-1 self-service
- [ ] 2.3 Worker polyfill (shim-polyfill.js): `runtime.onMessage` dispatch passes a real `sendResponse` and honors `return true` = async-response-open; on `sendResponse`, post `{__shim:'response', id, result}` back through the host page relay to native
- [ ] 2.4 Wire inbound native→content push into the page isolated world (content-shim `__muninnContentPush` → `runtime.onMessage`/`onMessageExternal` listeners); sender identity `{tab,frameId,url,id:canonical}`
- [ ] 2.5 Confirm canonical identity (`runtime.id`) is presented where fork.js / the account app read it (ADR-008)

## 3. Headless pre-gate verification

- [ ] 3.1 XCTest: inbound native→content push round-trip (broker → page isolated world → listener fires) — so only the *authenticated* half is unverified at the gate
- [ ] 3.2 XCTest/diagnostic: shell loads a page; fork.js injects on `account.proton.me` (host-scoped) and not elsewhere; MAIN-world isolation still holds in the real tab
- [ ] 3.3 Full suite green from a pristine clone (all prior tests + new)

## 4. The human gate (auth-fork-login — the Risk-1 go/no-go)

- [ ] 4.1 **[HUMAN GATE — ground rule 2]** Warn Calvin; on his confirmation, launch the app (visible window)
- [ ] 4.2 **[HUMAN GATE — ground rule 1]** Calvin navigates to `account.proton.me` and logs in himself; Muninn never touches credentials. Observe the background host session-pickup event ≤5 s under canonical ID; capture only non-credential signals (event presence/timing)
- [ ] 4.3 Record Calvin's verbatim verdict + the cookie/store topology finding in `research/e6-auth-fork-<date>.md`; **on failure, STOP and record the D4 decision** (no papering over)

## 5. Review & ship

- [ ] 5.1 Refute-oriented review (MAIN-world isolation still airtight with a real navigable tab; no credential leak on any new path — address bar, relay, push; context-routing correctness)
- [ ] 5.2 Ship via git-ship (PR-gated); update `CLAUDE.md`. **If the gate passed: Risk 1 is retired — E4/E5/E7/E8 unblocked. If it failed: record D4 and pause the skeleton.**
