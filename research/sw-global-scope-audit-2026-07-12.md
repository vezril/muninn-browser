# S1 — background.js global-scope audit — 2026-07-12

**Spike:** S1 (ADR-001/ADR-005; e2-e3-shim-core background-host spec).
**Method:** Headless boot of the vendored Proton Pass v1.38.0 `background.js` inside Muninn's background host (hidden WKWebView → DedicatedWorker substrate, per the ADR-005 refinement), with the Tier-1 polyfill's Proxy audit channel capturing every un-modelled API access and the worker's console/error/unhandledrejection streams forwarded to native. Run via `MUNINN_SHIM_DIAGNOSTIC=1` (25 s settle).

## Result: **CLEAN**

- `background.js` top-level executed to completion in the DedicatedWorker: `importScripts("background.js")` returned without throwing (`backgroundLoaded` event).
- **Zero** worker errors, **zero** unhandled rejections over the settle window.
- **One** audited API access, triaged benign (below).
- WASM crypto chunks and webpack `importScripts` chunk loading resolved against the `muninn-ext://` scheme without error.

This retires the S1 risk for the background host: the substrate that failed under CEF Alloy and JCEF (Spike A) boots Proton's real service worker clean on WKWebView + the shim. Deeper behavioral exercise (login/unlock/autofill) is E6/E7; this audit covers boot-time global-scope assumptions (Spike B risk 3).

## Audited API accesses

| API | kind | count | Triage |
|---|---|---|---|
| `chrome.app` | namespace probe | 1 | **Tier 3 — benign.** `chrome.app` is a legacy Chrome namespace (mostly an empty object in modern Chrome). Pass feature-detects it once at boot; no `chrome.app.<member>` call follows. The polyfill returns an (empty) namespace proxy, so the probe is harmless. No action needed; a real ServiceWorker would expose the same empty-ish object. Left auditable (not silently whitelisted) so a future *call* into it would resurface. |

## Worker errors / rejections

_none_

## ServiceWorkerGlobalScope-specific usage

None observed at boot. Consistent with the static grep (Spike B / E1 re-grep): `skipWaiting`, `clients`, `registration`, `caches` are absent from the bundle. `self.oninstall` is set but does not fire in a DedicatedWorker — it only lazy-loads the zip/csv export chunks (out of skeleton scope; import/export features, not login/autofill).

## Boot event timeline

```
hostStarting            version=1.38.0
host:pageReady          (host page loaded, manifest fetched over scheme)
host:workerReady        (polyfill initialized; self.chrome/self.browser installed)
host:backgroundLoaded   (background.js top-level ran clean)
```

## Disposition

**Zero untriaged entries — the FR-7 gate bar for E8 is met for boot-time audit.** E8 re-checks this against the full login+unlock+autofill run (which exercises far more of the API surface); this artifact covers the boot slice. Re-run `tools`/the diagnostic on every Pass version bump (rides the FR-25 cadence).
