# S2 spike — fork.js fallback + MAIN-world isolation — 2026-07-12

**Spike S2** (ADR-007 / architecture §5a): verify that inside Muninn's WKWebView the `fork.js` postMessage-fallback path is what gets exercised, and that nothing leaks `browserAPI`/`chrome` into a page's MAIN world. Gates E6.

## Verified (this change, execution-grounded)

1. **MAIN-world isolation — the load-bearing S2 guarantee. VERIFIED.** On a loaded page, `window.chrome` and `window.browser` are both `undefined` in the MAIN world, and `window.webkit.messageHandlers.brokerIsolated` is unreachable from the MAIN world (`ForkBridgeIsolationTests.testMainWorldIsIsolatedFromShim`, `testBrokerHandlerNotReachableFromMainWorld`, hermetic). The shim lives only in a named isolated `WKContentWorld`; a hostile page cannot see or call it.
2. **Relay plumbing — VERIFIED.** An isolated-world `browser.runtime` call round-trips through the native broker as a distinct second context and returns; payloads stay opaque (`testIsolatedRelayReachesBroker`).
3. **fork.js scoping — VERIFIED.** `fork.js` is injected only when the host matches the vendored manifest pattern (`account.proton.me` + subdomains), not on other origins (`testForkHostMatching`, pure).

## Fallback-selection reasoning (verified by corollary; live authenticated observation → E6)

Proton's account app selects its transport via `sendMessageSupported()`, which checks for `browserAPI?.runtime?.sendMessage` **in the page world** (research 2.1). Because our MAIN-world isolation is proven — `window.chrome`/`window.browser` are `undefined` in the page world — `sendMessageSupported()` is necessarily `false`, so the account app **must** take the `window.postMessage` fallback, which is exactly the path `fork.js` (injected in the isolated world) relays. The selection is therefore a direct corollary of the verified isolation + research 2.1, not an assumption.

What is **not** done here (correctly deferred to E6, ground rule 1): loading `account.proton.me` and completing a real login to watch the authenticated session handoff end-to-end. That is the E6 human-gated go/no-go; this spike stops at isolation + plumbing + selection-precondition.

## Timer-throttling (companion finding, resolved)

The E3 residency finding (hidden-page JS timer throttling) is fixed in this same change with a **public** lever (`inactiveSchedulingPolicy = .none`) — bisect in `nfr10-residency-2026-07-12-post-mitigation.md`. Relevant to S2/E6 because Proton's login/session code may use raw JS timers; those now run at full fidelity in the host.

## E6 go/no-go

**GO for E6**, with two carries:
1. **E6 owns the authenticated handoff** — load account.proton.me, Calvin logs in at the human gate, observe the fork.js relay deliver the real session to the background host. That is E6's first go/no-go gate, unchanged.
2. **Dedicated-data-store cookie sharing** — the host now uses a dedicated `WKWebsiteDataStore` (for timer-throttle process isolation). Verify at E6 that the auth-fork handshake does not depend on the host and the `*.proton.me` tab sharing a cookie store; if it does, reconcile the store topology.
3. **Inbound native→content push is unwired (by scope).** This change verifies the content→native relay + isolation, which is what S2 needs. The *reverse* path — native delivering an event into the page's isolated world — is a stub: `broker.pushEvent` targets the background host and the MAIN-world `__shimPush`, whereas `content-shim.js` exposes `__muninnContentPush` in the isolated world, and the injector never registers itself as an event target. `runtime.onMessageExternal` in the content shim is therefore an inert sink. This is fine because the fork.js handshake uses the `window.postMessage` fallback (verified selected above), **not** `onMessageExternal` — but E6/E5 must wire the isolated-world inbound push when they build the real multi-context messaging, and confirm the login path never depends on `onMessageExternal` delivery. (Review finding 2, 2026-07-12.)
