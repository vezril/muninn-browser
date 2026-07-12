# NFR-10 residency measurement — Pass v1.38.0

Headless idle run, 300 s, sampled every 15 s (`.prohibited` activation, no window). Non-binding for e2-e3; the binding 30-min measurement is E11's.

## Memory — PASS

| metric | avg | peak | target | verdict |
|---|---|---|---|---|
| App process phys_footprint | 32.5 MB | 168.5 MB | — | (peak is a transient boot spike; avg 32.5 MB) |
| WebContent (background host) RSS | 33.4 MB | 68.3 MB | NFR-10 ≤150 MB | **PASS** |
| App + host peak | — | 236.8 MB | NFR-3 ≤400 MB | **PASS** |

## ⚠️ Finding — hidden-page JS timer throttling (ADR-005 risk 7, CONFIRMED)

The hidden worker's `setInterval(1000)` fired **4 times in 300 s** (expected ~300). WebKit aggressively throttles JS timers in a non-visible WebView (the background host is created `frame: .zero` and never added to a window; `.prohibited` activation likely makes this worst-case). This is exactly the risk ADR-005 flagged and said would be "re-verified at NFR-10's E3/E11 gates" — and it is real.

**Impact assessment:**
- **Primary periodic mechanism is unaffected.** Pass drives periodic work through `chrome.alarms` (47 call sites in the inventory), which the shim maps to a native `DispatchSourceTimer` — NOT subject to WebKit timer throttling (the `alarm-fire` scenario and `testAlarmFires` both pass). So the load-bearing periodic path is safe.
- **Secondary risk:** any `background.js` logic relying on raw `setTimeout`/`setInterval` for runtime behavior (debounces, retries, polling) would be severely throttled while the host is hidden. Not exercised at boot (S1 was clean), but could surface in the E6 login/session flows.

**Triage / disposition:** documented finding, mitigation scoped as **E3-hardening, to burn down before E6's real login flow is validated**. Candidate mitigations (to spike): host the WebView in an off-screen/occluded 1×1 `NSWindow` so WebKit treats the page as visible; or a WebKit throttling opt-out (`_setWindowOcclusionDetectionEnabled` / page-activity API). Not a quick config flag — deserves its own focused verification (does the mitigation actually restore timer fidelity without a visible window?). Does NOT block the S1/round-trip correctness this change establishes.

## Method

App footprint via mach `task_vm_info.phys_footprint`; WebContent RSS via `ps -o rss` on the host's `_webProcessIdentifier`; timer fidelity via a `setInterval(1000)` tick counter in the worker, read back through the `__report` channel. Run: `MUNINN_SHIM_DIAGNOSTIC=1 MUNINN_SHIM_MEASURE=1 MUNINN_SHIM_MEASURE_SECS=300`.
