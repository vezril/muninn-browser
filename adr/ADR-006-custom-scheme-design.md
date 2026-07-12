# ADR-006 — Custom URL Scheme for Extension Resources

**Status:** Accepted (needs spike — S6: initiator identification for scheme requests; see Consequences)
**Date:** 2026-07-11
**Source IDs:** FR-8, FR-14, FR-15, FR-16, E4
**Evidence:** `research/spike-b-proton-pass-api-inventory.md` (Tier 2: WKURLSchemeHandler, web-accessible resources, WASM MIME); `research/2.1-bundle-acquisition.md` (bundle contents)

## Context

The extension expects `runtime.getURL()` to yield URLs that pages can embed (dropdown/notification iframes) and extension pages can load (popup, background). Chrome uses `chrome-extension://<id>/`. Muninn must serve the vendored bundle over something WKWebView treats as a real origin, with **web-accessible-resource semantics**: `dropdown.html`, `notification.html`, and `*.wasm` embeddable/fetchable from any `http(s)` page; everything else (background.js internals, popup.html) blocked from page-initiated loads. WASM must be served with the correct MIME type or Pass's crypto fails.

## Decision

1. **One custom scheme, `muninn-ext://`, registered via `setURLSchemeHandler` on every `WKWebViewConfiguration`** (page tabs, background host, popup, dropdown iframes). The handler reads exclusively from the vendored bundle directory (ADR-001) — it never touches the network.
2. **Authority component pins the extension identity:** URLs take the form `muninn-ext://ghmbeldphafepmbegfdlkpapadhbakde/<path>`, mirroring `chrome-extension://` URL shape so `runtime.getURL()` string manipulation in Pass code keeps working, and consistent with ADR-008's identity presentation.
3. **Web-accessible-resource enforcement lives in the handler:** it derives the allowlist from the vendored `manifest.json`'s `web_accessible_resources` at load time (never hardcoded — survives Proton manifest changes via the FR-25 gate). **Initiator identification is the hard part and is spike-gated (S6):** `WKURLSchemeTask` does not expose the requesting frame; `request.mainDocumentURL` is the main usable signal, and for **subresources loaded by the dropdown iframe itself** (a `muninn-ext://` document embedded in an `https` page — the primary risk-2 flow, not an edge case) the main document is the *page's* https URL, so naive main-document classification would misfile extension-frame requests as page-initiated and, under deny-by-default, 404 the dropdown's own assets. Intended resolution, verified by S6 before E4 is declared done: classify by the request URL/referrer chain (a request *for* an extension-origin subresource whose referrer is extension-origin is extension-initiated) and cross-check that all dropdown/notification subresources are WAR-listed in the vendored manifest (in which case the distinction is moot for those paths). E4's mandatory tests include this case as load-bearing.
4. **Correct MIME table** (js, html, css, json, wasm, svg, png, woff2) with `application/wasm` explicitly covered; responses carry no caching surprises (immutable bundle → long-lived cache headers are fine within a run).

## Consequences

- The dropdown iframe (Spike B risk 2's mechanics) gets a real, stable origin distinct from every web page — CSP on strict sites governs whether a page may *embed* the iframe (`frame-src`); pages that block all framing are the risk E7's strict-CSP target site exists to probe. The scheme choice cannot fix that; it only avoids adding new failure modes (data:/blob: URLs would).
- Deriving the allowlist from `manifest.json` makes E4's behavior track the vendored bundle version automatically — one less thing FR-25 re-triage must remember to update.
- One handler instance shared by all configurations keeps behavior identical across contexts; its statelessness (pure read of an immutable directory) makes it trivially testable (FR-8's acceptance: third-party embed OK, non-WAR path 404, WASM executes).
- The initiator-identification gap (decision 3) is the load-bearing open item — spike S6 resolves it before E4 exit. Secondary edge cases (about:blank subframes, srcdoc) ride the same tests. Fallback posture stays deny-by-default for genuinely unclassifiable requests, with the S6-verified classification ensuring the dropdown's own flow is never in that bucket.
