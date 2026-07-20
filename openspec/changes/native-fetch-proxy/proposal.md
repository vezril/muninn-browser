# Proposal: native-fetch-proxy

## Why

The E6 auth-fork login reaches the session-fork step and fails ("Unable to Sign In.
Unknown error"). Root cause (confirmed, `research/e6-external-gate-2026-07-17.md` +
`ForkCorsProbeTests`): `background.js` consumes the fork via
`fetch("https://pass.proton.me/api/.../sessions/forks/{selector}", {credentials:"include"})`
from the background worker, whose origin is `muninn-ext://<id>` (custom scheme). A
custom-scheme origin carries no host-permission privilege in WKWebView, so the
cross-origin request is CORS-blocked (`TypeError: Load failed`). In a real browser the
extension's `host_permissions` grant CORS-bypass; we must reproduce that privilege.

## What

A native `URLSession` fetch proxy that the extension worker's `fetch` is transparently
routed through for `host_permissions`-scoped hosts, bypassing CORS (native requests are
not subject to web CORS). Full design + options analysis:
`research/native-fetch-proxy-design-2026-07-18.md` (webkit-developer). Chosen: **option
(a)** — a `fetch` override in the worker bootstrap tunneling through the existing
worker↔page↔native bus to a native `URLSession`. Zero private API.

## MVP cutline (this change)

Enough to pass the auth-fork gate: `GET` requests to `*.proton.me`, buffered JSON
responses (`status`/`statusText`/`headers`/`.json()`/`.text()`), safe header passthrough,
`credentials:"include"` via a dedicated native cookie jar, `AbortSignal`→cancel.

**Deferred:** streaming/`ReadableStream`, request bodies beyond string/ArrayBuffer
(FormData/Blob/multipart), XMLHttpRequest, Range/partial, `redirect:"manual"`.

## Security (deny-by-default — the SSRF boundary)

1. **Handler locality:** the `__fetch` route is wired ONLY on the background host's
   `broker` handler — never on the page's `brokerIsolated`. Untrusted tabs cannot reach it.
2. **Host allowlist (native):** scheme must be `https`; host must satisfy a proper suffix
   match (`== "proton.me"` or `.hasSuffix(".proton.me")`), never a substring test.
3. **Redirect containment:** re-check the allowlist on each redirect; stop if it leaves.
4. Strip `Cookie`/`Host`/`Content-Length` from JS-supplied headers; cookies are
   native-managed.

## Impact

Unblocks E6 (auth-fork consume). New: `NativeFetchProxy` (actor), a `__fetch` broker
route, a worker `fetch` override. Side-steps Decision 4 (cookies move to a dedicated
native `HTTPCookieStorage`). Relates to ADR-002 (proxy routing) / E8 (egress audit —
the proxy is the natural chokepoint for the FR-22 allowlist later).
