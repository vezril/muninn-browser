# Native fetch proxy — design (E6 auth-fork unblock)

**Date:** 2026-07-18. Source: webkit-developer agent, grounded in the WebKit embedding
reference + ADR-007. Problem: the extension worker (`muninn-ext://<id>` origin) can't
`fetch` `https://pass.proton.me/api` — CORS-blocked (confirmed `TypeError: Load failed`).

## Options considered

| Option | Verdict |
|---|---|
| **(a) `fetch` override → bus → native `URLSession`** | **RECOMMENDED** — zero private API; reuses the E2/E3 bus; every fidelity gap is deferrable |
| (b) `WKURLSchemeHandler` for `https://pass.proton.me/*` | **Impossible** — WebKit rejects handlers for schemes it already handles (`http/https/file/…`); custom schemes only |
| (c) `WKWebExtension` / `WKWebExtensionController` | Gets host-permission CORS-bypass free, but **all-or-nothing** — hosts the ENTIRE extension, deletes our purpose-built shim, raises the deployment floor to macOS 15. Contradicts the project decision. Not incremental. |
| (d-i) SPI `_webSecurityEnabled=false` | Reject — private AND global (kills SOP for the whole webview) |
| (d-ii) loopback reverse proxy | Reject — listening socket, TLS-origin confusion, no advantage over in-process |
| (1a) rewrite to a custom `muninn-ext-proxy://` scheme + scheme handler | Future streaming upgrade only — `WKURLSchemeTask` drops POST bodies (`httpBody` nil); additive to (a), not simpler |

## Recommendation: Option (a)

A `fetch` override in the worker that tunnels through the existing bus to a native
`URLSession` proxy, with a hardcoded `*.proton.me` allowlist + redirect containment.

### Critical correctness point
`WKUserScript` / `webkit.messageHandlers` **do not reach DedicatedWorker scope.** Install
the `fetch` shim in the **worker bootstrap** (the script that runs
`importScripts(background.js)`), BEFORE importing Pass's code, so `globalThis.fetch` is
replaced at worker start. It relays over the existing worker↔page `MessageChannel` → host
page broker-glue → `webkit.messageHandlers.<broker>` → native. **New envelope kind only**
(`fetchProxy` / `fetchProxyChunk` / `fetchProxyAbort`), reusing ADR-007 `msgId`
correlation + parked continuations. No new native transport.

### JS shim (worker bootstrap)
- Keep original `fetch`. Route by URL: `http(s)` + host on allowlist → proxy; else
  (`muninn-ext://`, `blob:`, `data:`) → original (so the worker still loads its own resources).
- Normalize `Request`: method, URL, safe header subset (DROP `Cookie`/`Host`/`Content-Length`;
  pass `x-pm-uid`, `x-pm-appversion`, `authorization`, `content-type`, …).
- Body: `string` + `ArrayBuffer`/TypedArray (base64) for MVP; FormData/Blob deferred.
- `AbortSignal` → `fetchProxyAbort{msgId}` → cancel the `URLSessionTask`; reject `AbortError`.
- Reply → `new Response(bytes, {status, statusText, headers})` (full, CORS-clean).

### Native (Swift 6 / macOS 26.2)
- A `NativeFetchProxy` **actor** (NOT `@MainActor`) owning one `URLSession`. `@MainActor`
  `MessageBroker` receives the envelope, validates scope on the main actor, then `await`s
  the proxy actor (network work off the main actor).
- `try await session.data(for: request)`; marshal back
  `{status, statusText, headers:[[k,v]], bodyBase64, finalURL, redirected}`. Buffer the whole
  response (Proton API payloads are small JSON) — no streaming for MVP.

### Security — deny by default (SSRF boundary)
1. **Handler locality (primary):** register the `fetchProxy` handler ONLY on the background
   host's `userContentController`. Content webviews (account tabs, arbitrary sites) can't
   reach it.
2. **Host allowlist (native, hardcoded):** scheme must be `https`; host must satisfy a
   proper suffix match — `host == "proton.me" || host.hasSuffix(".proton.me")` (NEVER a
   substring test). Tighten to the specific API hosts if the re-grep confirms the set.
3. **Redirect containment:** `URLSessionTaskDelegate…willPerformHTTPRedirection` re-runs
   the allowlist; return `nil` to stop if it leaves the allowlist (prevents an open redirect
   from carrying the extension's cookies off-allowlist).
4. Enforce the forbidden-request-header set natively (JS bypasses page enforcement).

### Cookies / Decision-4 — side-stepped
Native `URLSession` cookies live in `HTTPCookieStorage`, distinct from both WK data stores.
Give the proxy its **own dedicated `HTTPCookieStorage`** (private
`URLSessionConfiguration.httpCookieStorage`, persisted under Application Support) = the
extension's Proton session, isolated from `URLSession.shared`. The fork *selector* is
exactly the mechanism to transfer session state WITHOUT sharing cookies (account tab holds
the web session in the WK store; the extension establishes its OWN session via the fork
endpoint), so `credentials:"include"` wants the extension's native jar — consistent, no
cross-tab leakage, invisible to JS (workers have no `document.cookie`). This removes the
Decision-4 coupling on the fetch path entirely.

## MVP slice (to pass the auth-fork gate)
`GET /api/auth/v4/sessions/forks/{selector}`: GET; safe header passthrough; no body;
follow redirects within allowlist; buffered response with `status/statusText/headers`;
`.json()`/`.text()`; `credentials:"include"` via native jar; `AbortSignal`→cancel.

**Defer:** `ReadableStream`/incremental body (buffer instead); request bodies beyond
string/ArrayBuffer; **XMLHttpRequest** (re-grep whether any `*.proton.me` traffic uses XHR —
Pass is fetch-based; confirm); Range/partial; `redirect:"manual"` fine-grain.

## To verify before relying on load-bearing claims
- Exact `WKWebExtension` availability floor (agent flagged: doc didn't render; ~macOS 15).
  Not needed for option (a).
- `WKURLSchemeTask` POST-body `nil` limitation vs the 26.2 SDK — only matters for the (1a)
  upgrade path.
- Whether the worker bootstrap is a place we control to override `fetch` before
  `importScripts(background.js)` — inspect `Muninn/Shim/Resources/background-host-page.js`
  + the worker bootstrap.

## Scope
This is a distinct subsystem (native extension networking; relates to ADR-002 proxy
routing / E8), most naturally **its own OpenSpec change/epic** that the E6 walking-skeleton
login depends on.
