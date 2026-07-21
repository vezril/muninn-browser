# Tasks: native-fetch-proxy

## 1. Native proxy actor

- [x] 1.1 `NativeFetchProxy` (actor, `Muninn/Shim/NativeFetchProxy.swift`): one `URLSession` with a dedicated `HTTPCookieStorage` (extension session, isolated from `.shared`). `perform(url:method:headers:bodyBase64:) async -> FetchResult` (Sendable) → status/statusText/headers/bodyBase64/finalURL/redirected or `.error`. Buffered (no streaming).
- [x] 1.2 Allowlist (`https` + `host == "proton.me" || host.hasSuffix(".proton.me")`, proper suffix) checked on the request AND on each redirect (`RedirectGuard`/`willPerformHTTPRedirection` → nil off-allowlist) + a final-hop guard. Strips forbidden request headers (Cookie/Host/Content-Length).

## 2. Broker route (host-only)

- [x] 2.1 `MessageBroker.performFetch(_ env) async -> Any?` — parses the spec into Sendable primitives on the main actor, `await`s the `NativeFetchProxy` actor, marshals the JS reply. Holds a `NativeFetchProxy`.
- [x] 2.2 `BackgroundHost.HostBridge` async handler routes `ns=="__fetch", method=="request"` to `broker.performFetch`; the page's `IsolatedBridge` does NOT (locality — verified by test). _AbortSignal→cancel deferred (fork GET doesn't abort)._

## 3. Worker fetch override

- [x] 3.1 In `shim-polyfill.js` (has `callNative`), at the end of the IIFE — runs during `importScripts("shim-polyfill.js")`, before `background.js`: replaces `self.fetch`. Routes `http(s)` + allowlisted host (`endsWith(".proton.me")`) → `callNative("__fetch","request",[spec])`; else the platform `fetch`.
- [x] 3.2 Marshals `Request`→spec (method, url, safe headers, string/ArrayBuffer body→base64) and response→`new Response(bytes,{status,statusText,headers})`. _FormData/Blob/stream bodies + AbortSignal deferred._

## 4. Tests

- [x] 4.1 Unit: allowlist suffix match (`testAllowlistSuffixMatch` — proton.me, sub.proton.me pass; evilproton.me, proton.me.evil.com, http, example.com fail).
- [x] 4.2 Headless net-gated: worker `fetch` to `pass.proton.me/assets/version.json` **succeeds through the proxy — status 200** (`testWorkerProxiedFetchSucceeds`; the counterpart to `ForkCorsProbeTests`' raw-fetch CORS failure). Fixed an off-by-one in the JS allowlist (`.proton.me` is 10 chars) found by this test.
- [x] 4.3 Locality: a page/isolated-world `__fetch` call is rejected, not proxied (`testProxyNotReachableFromPage`).
- [x] 4.4 Full suite green — **40 tests, 0 failures** (2 net probes skipped).

## 4b. Diagnose why the fork consume never reaches the worker fetch proxy

> **Gate 8 (2026-07-20) — corrected:** with the fetch proxy live, `fork → RESPONDED`
> but login still "Unknown error", AND the fetch probe logged **zero** proxied requests
> and **zero** worker errors. My first read ("it's XHR") was WRONG: only **Sentry** uses
> `XMLHttpRequest`; Proton's API client is **`fetch`-based** (`{mode:"cors",
> credentials:"include", redirect:"follow", signal}`). So the fork consume never called
> the worker's overridden `fetch`. Either (A) the fork handler fails BEFORE the network
> call (caught → responds "error"), or (B) the consume runs in the **account tab**
> (fork.js content script, same-origin to account.proton.me → no CORS, no worker fetch),
> and the failure is elsewhere.

- [x] 4b.1 Added a safe **fetch-entry probe** (host only, before the allowlist decision) so the next gate shows whether the worker calls `fetch` during the fork and to which host — distinguishing (A) from a routing bug.
- [ ] 4b.2 Next gate OR live-inspect the background worker console (inspectable in gate mode) to read the fork handler's actual caught error. Ground rule 1: host/method/status markers only; background console `warn/error` may carry sensitive text — do NOT blanket-capture.
- [ ] 4b.3 Fix per the finding (could be: a worker fetch that isn't being routed; a pre-fetch failure in the handler; or the consume being an account-tab same-origin call that fails for a different reason).

## 5. Verify, review & ship

- [ ] 5.1 Refute-oriented review (SSRF boundary: locality + allowlist + redirect containment; no header injection; cookie-jar isolation; Swift 6 actor correctness).
- [ ] 5.2 **Live gate:** re-attempt the E6 auth-fork login; the fork consume should now complete past "Unable to Sign In." Ground rules 1+2 — gate log stays type-only, never the selector/session/credentials.
- [ ] 5.3 Ship via PR-gated flow; update `CLAUDE.md` + the E6 checkpoint (fork consume unblocked).
