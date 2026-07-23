# Design: e6-auth-fork-login

## Context

The shim core is done and headlessly proven: background host boots Proton's `background.js` clean, the broker round-trips, and S2 proved the shim is confined to an isolated content world with `fork.js` injectable on `account.proton.me`. What's missing is (a) a real navigable window/tab to load `account.proton.me` and (b) the *bidirectional* handshake: content→native works (S2), but native→content is unwired (S2 review finding 2). E6 closes both, then hands off to Calvin for the actual login — which no automated test can perform (ground rule 1). This change is build-to-the-gate, then human-drive.

## Goals / Non-Goals

**Goals:**
- One window, one tab, address bar + back/forward/reload; loads `account.proton.me` and an arbitrary URL (FR-1/4/5).
- `fork.js` injected on `account.proton.me` (isolated world), the account app's `postMessage` handshake relayed through the broker to the background host, and the host's response pushed back into the page's isolated world.
- Session pickup observed at the background host within 5 s of Calvin's manual login, under the canonical extension ID.
- Dedicated-store cookie assumption verified (does the handshake need the tab and host to share a store?).

**Non-Goals:**
- Popup / vault unlock UI (FR-14) and autofill dropdown (FR-15) — **E7**.
- Multi-tab, session restore, downloads, default-browser (FR-2/3/27/28/29) — **E9**.
- The general FR-9 InjectionCoordinator + frame registry — **E5** (E6 keeps the minimal S2 injector).
- Full port semantics — remains E-scope as messaging matures.

## Decisions

1. **AppShell replaces the diagnostic-only launch path.** `AppDelegate` gains a real `.regular` app: an `NSWindow` hosting a `TabViewController` with one `WebTab` (a page `WKWebView` built by a promoted `ForkBridgeInjector`), an `NSTextField` address bar, and toolbar back/forward/reload bound to the WebView's navigation. The `MUNINN_SHIM_DIAGNOSTIC` headless paths stay for CI/measurement.
2. **The core is a cross-context request/response message bus — bigger than "relay" (REVISED 2026-07-12 during apply; ratified: revise-design-first). This is the load-bearing new work, ~400–500 lines.** `runtime.sendMessage` from the page must be *delivered to `background.js`'s `onMessage` listener in the host Worker*, and that listener's response correlated back across two process boundaries (page WebView ↔ native broker ↔ host page ↔ host Worker):
   - **Broker context registry.** The broker tracks named contexts, each with a native→JS push delivery + origin tag. At E6: `host` (background Worker, via the host page MAIN-world `window.__shimPush` → worker) and `page` (the tab's isolated world, via `evaluateJavaScript(…, in: isolatedWorld)` → content-shim `__muninnContentPush`). `pushEvent` takes an explicit target — no blanket broadcast.
   - **Cross-context `sendMessage` becomes async with correlation.** The synchronous `handle()` stays for Tier-1 self-service (storage/alarms/…), but a page-origin `runtime.sendMessage` allocates a correlation id, delivers a `runtime.onMessage` event to the `host` worker carrying `{message, sender, __respId}`, and parks a continuation; the `brokerIsolated` handler is already the async reply variant, so the page awaits naturally.
   - **Chrome onMessage contract in the worker (shim-polyfill.js change).** `fireEvent("runtime.onMessage", …)` must pass a real `sendResponse` and honor **`return true` = keep channel open for async `sendResponse`** (background.js relies on this; today it fire-and-forgets). On `sendResponse(resp)` the worker posts `{__shim:'response', id, result}` back through the host page relay → native → broker resolves the parked continuation → value returns to the page reply.
   - **Sender identity** for a page-origin message: `{tab, frameId, url, id:canonical}` — minimal but present, since fork.js/background.js may inspect it.
3. **fork.js relay path end-to-end (research 2.1), on the bus above:** account app (MAIN world) `window.postMessage` (fallback — `chrome.runtime` absent, verified S2) → `fork.js` (isolated world) → `browser.runtime.sendMessage(sessionData)` → content-shim → `brokerIsolated` → broker → **`runtime.onMessage` into the host Worker (background.js) — this delivery is the pickup** → background.js processes + `sendResponse(confirmation)` → broker → back to fork.js's promise → `window.postMessage` to the account app. **Minimum for the Risk-1 gate = delivery to background.js;** the response leg is required if the account app awaits confirmation before completing the fork (likely) — implement both, gate verdict hinges on pickup.
3b. **Canonical identity (ADR-008):** content-shim already presents `runtime.id = ghmbeld…`; verify the account app / fork.js see it where they look.
4. **Cookie/store topology check (E3-hardening carry):** the login happens in the *page tab* (its own store); the background host has a *dedicated* store. The auth-fork passes the session via postMessage, not shared cookies, so they *should* be independent — but the background host then makes Proton API calls that need the forked session. Verify empirically at the gate whether the host can act on the session without sharing the tab's cookie store; if it can't, reconcile (e.g. host joins the default/page store, re-checking the timer-throttle process-isolation requirement — a real tension to resolve, not assume).
5. **Human gate is the test.** Build + headless-verify everything verifiable (shell loads pages, injection fires on proton.me, inbound push delivers a synthetic event round-trip). Then: warn → Calvin confirms → launch → Calvin logs in → observe pickup. Record verbatim verdict. No credential capture anywhere.
6. **D4 on failure, no papering.** If pickup fails after reasonable debugging, STOP; record the failure and the D4 decision (fix-in-shim vs pinned-tab Pass web app vs CEF). This is the gate the whole engine choice rides on.

## Risks / Trade-offs

- [account app doesn't take the postMessage fallback / fork.js doesn't fire] → the top risk. Debug via the isolated-world channel (observe whether `fork.js` receives the page postMessage); S2 verified the precondition (MAIN-world `chrome.runtime` absent), so the fallback *should* be selected — but the live account app is the real test.
- [Background host can't act on the session without the tab's cookies (Decision 4)] → may force the host onto a shared store, colliding with the E3-hardening dedicated-store requirement; if so, surface the fidelity-vs-session trade to Calvin rather than silently changing the topology.
- [Inbound push races / wrong context] → the broker must tag contexts; test the native→content round-trip headlessly before the login gate so only the *authenticated* half is unverified at the gate.
- [GUI window on Calvin's machine] → strict ground rule 2: warn and wait for his ready before any launch; he closes stray windows (killed three Spike A runs).
- [Credential exposure] → the console-capture redaction (warn/error only) from e2-e3 already applies to the host; ensure no new log path (address bar, nav, relay) records page content or tokens.

## Migration Plan

Additive. The diagnostic/headless entry points remain. Rollback = revert; no persisted-state migration beyond the (already-present) dedicated store.

## Open Questions

- Decision 4 (cookie/store topology) — answered empirically at the gate; may become an ADR if it forces a topology change.
- Whether fork.js needs anything beyond `runtime.sendMessage` + the inbound push (e.g. a specific message shape) — observed live; content-shim extended minimally if so.
