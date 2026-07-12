# ADR-007 — Message-Broker Contract

**Status:** Accepted — Calvin Ference, 2026-07-11 22:55 EDT (architecture.md §10)
**Date:** 2026-07-11
**Source IDs:** FR-10, FR-11, FR-13, NFR-8, E2, E6
**Evidence:** `research/spike-b-proton-pass-api-inventory.md` (runtime messaging — "the single most important piece"); `research/2.1-bundle-acquisition.md` (fork.js relay path)

## Context

Everything flows through `runtime` messaging: content scripts ↔ background, popup ↔ background, dropdown iframe ↔ background, fork.js's auth relay, and every Tier-1 namespace event (alarms firing, tabs.onUpdated, storage change notifications). Spike B calls the broker the single most important piece. WKWebView gives two primitives: `WKScriptMessageHandler` (JS → native, per content world) and `evaluateJavaScript(in:frame:contentWorld:)` (native → JS, frame- and world-targeted). The broker must reproduce `chrome.runtime` semantics faithfully enough that Proton's unmodified code works: async `sendMessage` with response callbacks/promises, persistent `Port` objects from `connect`/`onConnect` surviving many exchanges, correct `sender` metadata (tab id, frame id, origin), and delivery across three context types (page frames, background host, extension pages).

## Decision

1. **Topology: hub-and-spoke, native hub.** All messages route through the native `MessageBroker` (Swift actor); there is no direct JS↔JS path. The broker joins `WKScriptMessageHandler` receipts to a routing table keyed by `(webView, frameID, contentWorld)` — the FrameRegistry (FR-9) supplies frame identity.
2. **Wire contract: one envelope, versioned.** Every message crossing the boundary is `{brokerV: 1, kind: sendMessage|response|portConnect|portMessage|portDisconnect|event, msgId, portId?, sender, payload}`. `payload` is Pass's own JSON — **treated as opaque bytes: never parsed, logged, or persisted by the broker** (NFR-8/FR-21; routing decisions use envelope fields only).
3. **JS side: a single injected `browser`/`chrome` polyfill** (the Tier-1 stub layer's JS half, injected at `document_start` into the isolated world and the extension contexts — never the page's MAIN world, so nothing leaks `browserAPI.runtime.sendMessage` into page scope where it would defeat fork.js's fallback detection; research 2.1 S2). The polyfill implements callback/promise duality the way Chrome does (return value + `lastError`).
4. **Ports are broker-owned state:** `connect()` allocates a `portId` at the hub; each end holds a stub. Disconnect events fire on frame navigation/destruction, driven by FrameRegistry lifecycle callbacks — not by JS-side finalizers (unreliable).
5. **Delivery guarantees kept honest:** at-most-once, ordered per (sender, receiver) pair — same as Chrome's practical semantics. No retry/queue for a dead background host; instead the host watchdog (ADR-005) restarts it and content-script stubs surface `lastError` — which Pass is *expected* to handle as it does MV3 worker restarts (expected behavior, verified at S2/FR-25 re-grep, not asserted as fact per the API-tightness rule).
6. **`runtime.onMessageExternal` is exposed as an inert event surface** (registration succeeds, no events ever fire) so `background.js` listener registration cannot throw (FR-11's zero-TypeError acceptance; verified at S1). The approved FR-13 text names `onMessageExternal` as the relay mechanism — superseded by the fork.js reframe, flagged as a deviation at the architecture gate (architecture §10 item 3).

## Consequences

- The envelope's opacity rule makes the credential boundary (architecture §6) structural: there is no code path where the broker understands Pass payloads, so a logging bug can leak routing metadata at worst. The debug logger logs envelope fields only.
- Injecting the polyfill into the isolated world only is load-bearing twice over: it isolates Pass's API surface from hostile pages, and it keeps `window.chrome.runtime` absent in the MAIN world so account.proton.me picks the postMessage fallback (FR-13 via fork.js). `webauthn.js` (MAIN world per manifest) gets no `browser.*` API — matching Safari's real behavior; if re-grep (FR-25) ever shows it needing runtime APIs, that's a triage event.
- Versioning the envelope (`brokerV`) costs one field now and buys painless evolution when a Pass update demands new semantics.
- FR-10's acceptance (round-trip + 5-exchange port survival) tests the hub, the polyfill, and FrameRegistry integration together — E2's exit criterion exercises real wiring, not mocks.
