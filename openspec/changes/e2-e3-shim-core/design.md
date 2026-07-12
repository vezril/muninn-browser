# Design: e2-e3-shim-core

## Context

The architecture fixes the shape: hub-and-spoke broker as a Swift actor (ADR-007), hidden-WKWebView host (ADR-005), Tier-1 surface bounded by Spike B's Safari profile as re-validated 2026-07-11 (FR-25 artifact). The vendored bundle (v1.38.0) is on disk with `fork.js`/`background.js` verified. What this change must decide is the *internal* mechanics: how the polyfill reaches native, how `background.js`'s chunk loading is satisfied, and how the exit criteria get executed without the shell (no tabs until E6).

## Goals / Non-Goals

**Goals:**
- `background.js` boots in the hidden host with **zero unhandled `TypeError: browser.X.Y is not a function`** (FR-11 acceptance, S1 spike) — the boot log *is* the FR-7 global-scope audit input.
- Broker round-trip (test content context → background) works; a port survives ≥5 exchanges (FR-10 acceptance).
- Host survives a deliberate crash of a sibling WKWebView (architecture §6 isolation claim, made measurable).
- NFR-10 measured: host RSS ≤150 MB steady-state; JS timer fidelity over a 30-min idle window (ADR-005's hidden-page throttling check).

**Non-Goals:**
- No full FR-8 scheme semantics (WAR allowlist, page-embedded iframes, S6) — E4.
- No content-script injection into real pages, no frame registry (`runtime.getFrameId` included) — E5.
- No shell/tabs/navigation, no login flow, no fork.js exercise — E6 (S2 spike lives there).
- No MV3 suspend/wake emulation — deliberately absent (ADR-005).

## Decisions

1. **Polyfill transport:** one `WKScriptMessageHandlerWithReply` ("brokerPort") per **page/content** context; the JS polyfill wraps it behind `browser.*`/`chrome.*` with Chrome's callback/promise duality and `lastError`. Replies use the native reply handler for `sendMessage`; broker-initiated deliveries (port messages, events) use `evaluateJavaScript(in:frame:contentWorld:)`. **The background-host Worker is the exception** (per the ADR-005 refinement): a Worker cannot register a `WKScriptMessageHandler`, so its leg goes through the host **page** as a relay — the page holds the `WKScriptMessageHandlerWithReply` and shuttles envelopes to/from the Worker via `worker.postMessage`/`worker.onmessage`. The broker treats "host" as one logical context whose physical transport is page-handler ⇄ page ⇄ worker. Rationale: reply handlers give ordering + error propagation for free; the page relay is a thin, stateless envelope forwarder.
2. **Polyfill implementation: a JS `Proxy` catch-all over each namespace.** Stubbed members route to native; unstubbed member *access* returns a function that logs `{namespace, member}` to the audit channel and returns a rejected promise (MV3-ish behavior) rather than throwing at property access. This makes the FR-7 audit a **built-in instrument**, not a separate pass — every un-modeled API Pass touches lands in the audit log with a stack.
3. **Minimal scheme loader:** `muninn-ext://ghmbeldphafepmbegfdlkpapadhbakde/<path>` handler that (a) serves only to requests whose main document is itself extension-origin (the background host and future extension pages), (b) 404s everything else. This is a strict subset of ADR-006 — E4 *extends* it with manifest-derived WAR rules; nothing here needs undoing. MIME table includes `application/wasm` (the crypto chunks load at boot).
4. **`background.js` runs in a `DedicatedWorker`, not the page** (corrected 2026-07-12; ratified — see ADR-005 refinement). Static inspection of the vendored v1.38.0 artifact falsified the original premise: its sole webpack chunk loader is `importScripts` (`f.f.i`), a WorkerGlobalScope-only API absent on a WKWebView page main thread. The host loads a tiny `background.html` that does `new Worker("background.js", {type: "classic"})`; the Worker `importScripts`es its chunks and WASM against the `muninn-ext://` scheme (served by the loader). The polyfill (Decision 2) is injected into the Worker via a first `importScripts` of a generated `shim-polyfill.js` (or prepended), before `background.js` runs. Broker⇄host transport is `Worker.postMessage` / `self.onmessage`. Remaining worker-global assumptions surfacing at boot (`clients`, `registration`, etc. — grepped absent, but confirmed at runtime) go to the FR-7 audit log per triage, not pre-emptive emulation. `self.oninstall` won't fire; it only lazy-loads zip/csv export chunks (out of skeleton scope).
5. **Storage backing:** `storage.local` → JSON file under Application Support, wrapped with a Keychain-held encryption key (Spike B defense-in-depth; NFR-8); `storage.session` → in-memory dictionary. Both behind one Swift `ExtensionStorage` type so the E11 re-measure and any future migration touch one place.
6. **Alarms:** `DispatchSourceTimer` registry keyed by alarm name (Spike B's mapping), firing `alarms.onAlarm` through the broker's event path. Wall-clock (not monotonic) scheduling to survive sleep sensibly.
7. **Tabs/action/windows stubs return the truthful minimum:** there are no tabs yet, so `tabs.query` returns `[]`, `action.setBadgeText` records state for the future toolbar, `windows.*` no-ops with valid shapes. E6/E9 replace internals behind the same surface; the audit log flags any Pass boot path that *requires* a non-empty answer.
8. **Watchdog:** `webContentProcessDidTerminate` on the host triggers reload + a logged restart event; restart storms (>3 in 10 min) stop the watchdog and surface loudly instead of looping silently.
9. **Test harness: XCTest bundle (`MuninnTests`) driving real WKWebViews** (off-screen, no windows — `xcodebuild test` stays headless; if any step turns out to open a window, ground rule 2 applies and it moves behind the gated launch). The 30-min idle measurement is NOT an XCTest — it's a small script + one gated app launch, results recorded in the change.

## Risks / Trade-offs

- [background.js refuses to boot outside a real SW scope despite guards] → the audit log pinpoints the APIs; fallback ladder: shim the specific globals (likely small), else D4 line 1 applies. This is precisely S1's job — budgeted first, before broker polish.
- [Proxy-based polyfill masks a *behavioral* (not existential) API gap — call succeeds with wrong semantics] → exit criteria exercise real flows (round-trip, alarms firing, storage persist/reload), not just absence-of-throw; E6 is the deeper behavioral gate.
- [WKScriptMessageHandlerWithReply reply ordering vs port messages interleaving] → per-(context, port) FIFO enforced in the broker actor; test asserts ordered delivery across 50 interleaved messages.
- [Keychain wrap adds first-run friction (keychain prompt) in tests] → tests use an ephemeral in-memory key; only the app path touches the Keychain.
- [30-min measurements are slow/manual] → run once per change, recorded in-artifact; not part of the routine test suite.

## Migration Plan

Additive. Rollback = revert the PR; no persisted-state migration (storage files are new).

## Open Questions

- None blocking. (Whether `background.html`-as-classic-page vs a module worker inside the host page matters will be answered empirically by S1's boot log; both are shim-internal and swappable.)
