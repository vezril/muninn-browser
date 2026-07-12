# ADR-005 — Background-Host Substrate: Hidden WKWebView, Not JSContext

**Status:** Accepted — Calvin Ference, 2026-07-11 22:55 EDT (architecture.md §10)
**Date:** 2026-07-11
**Source IDs:** FR-7, FR-11, NFR-10, E3
**Evidence:** `research/spike-b-proton-pass-api-inventory.md` (Tier 2, background host); `openspec/changes/architecture-and-adrs/research/2.2-sandbox-distribution.md` (JIT entitlement analysis); `research/2.1-bundle-acquisition.md` (Safari bundle boot expectations)

## Context

Spike B left the substrate open: "hidden off-screen WKWebView (or JSContext)." `background.js` is a large webpack bundle expecting a browser-ish global scope: `fetch`, WebCrypto, WASM instantiation, IndexedDB-adjacent storage semantics behind the `storage` shim, timers, and chunk loading (`importScripts`-style or dynamic import depending on build flags). Research 2.2 adds a distribution-facing datum: JavaScriptCore running **in-process** (a bare `JSContext`) requires the `com.apple.security.cs.allow-jit` entitlement under hardened runtime, while WKWebView JITs untrusted JS inside Apple's own out-of-process WebContent sandbox — the host app needs nothing.

## Decision

**The background host is a hidden, non-rendering `WKWebView`** loading `background.js` via the custom scheme (ADR-006), kept alive for the app's lifetime (FR-7), with:

- its **own `WKWebsiteDataStore`**, distinct from the page-tab store (reliability isolation + egress-audit classification, architecture §6);
- a **process-level App Nap assertion** (`ProcessInfo.beginActivity`) held while the host runs — App Nap exemption is process-granular, so this is app-wide by nature; it is the *minimum necessary* exemption under NFR-10's wording (one assertion, dropped if the host is torn down). WebKit's separate hidden-page **timer throttling** (JS timer coalescing in non-visible views) is the other threat to `background.js` and is added to E3's verification scope (timer fidelity over 30-min idle); re-verified at NFR-10's gates rather than assumed;
- the Tier-1 stub layer (FR-11) injected **before** `background.js` executes, including the benign `nativeMessaging` no-op (FR-12) — the Safari manifest marks that permission *required*, so the stub is a boot precondition, not an optional nicety (architecture §8 risk 2). **⚠️ DEVIATION for ratification:** this promotes FR-12 from the PRD's P2/"MAY" (roadmap: E12) to an M1/E3 precondition — flagged for Calvin at the architecture gate (architecture §10).

A bare `JSContext` is rejected as the primary substrate.

## Consequences

- **Bought:** the full web platform for free (fetch, WebCrypto, WASM, CSP handling, chunk loading) — every gap a `JSContext` would force Muninn to polyfill by hand; out-of-process crash isolation (a background-host JS crash kills a WebContent process, not Muninn); zero hardened-runtime entitlement exposure if/when the app signs for distribution (ADR-003).
- **Paid:** a standing WebContent + Networking XPC footprint (bounded by NFR-10's 150 MB ceiling, measured at E3); one more WKWebView whose process can be terminated by the OS — mitigated by the same process-termination rebuild path as page tabs (architecture §8 risk 6), plus a watchdog restart for the host specifically.
- The MV3 lifecycle is deliberately NOT emulated: no suspend/wake, no event-driven wakeups — strictly simpler than Chrome's real semantics, per Spike B. If Proton's future code *depends* on suspension semantics (e.g., alarm-driven wake assumptions), FR-25's re-grep gate is where that surfaces.
- FR-7's global-scope audit (Spike B risk 3) runs against this substrate at E3 and gates M1 exit at E8.
