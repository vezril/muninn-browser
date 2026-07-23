# Design: native-fetch-proxy

Full options analysis + WebKit specifics: `research/native-fetch-proxy-design-2026-07-18.md`.
This is the condensed decision record.

## Decision 1 — transport: reuse the existing bus (no new envelope kind)

The worker's `callNative(ns, method, args)` already posts `{__shim:"call", id, …}` → the
host page relays to native via `webkit.messageHandlers.broker` (a
`WKScriptMessageHandlerWithReply`, which is `async`) → the reply resolves the worker's
promise. A fetch that `await`s `URLSession` simply delays that reply. So the proxy is a
new **namespace** (`__fetch`) on the existing bus, not a new transport.

## Decision 2 — where the `fetch` override lives

`WKUserScript` / `webkit.messageHandlers` do NOT reach DedicatedWorker scope, so the
override is installed in **`shim-polyfill.js`** (which owns `callNative`), at the end of
its IIFE — i.e. during `importScripts("shim-polyfill.js")` in the worker boot, BEFORE
`importScripts("background.js")`. `globalThis.fetch` is replaced there.

Routing: `http(s)` + host on allowlist → proxy via `callNative("__fetch","request",[spec])`;
everything else (`muninn-ext://` own resources, `blob:`, `data:`) → the original `fetch`.

## Decision 3 — request/response marshaling

Request spec: `{ url, method, headers:{k:v}, bodyBase64?:string }` (drop Cookie/Host/
Content-Length before sending). Response: `{ status, statusText, headers:[[k,v]],
bodyBase64, finalURL, redirected }` or `{ __error:"…" }`. The worker reconstructs
`new Response(bytes, {status, statusText, headers})` — a full, CORS-clean Response, so
`.ok/.status/.json()/.headers.get()` all work. (`response.url` is `""` for a constructed
Response — acceptable for the fork GET; a scheme-rewrite upgrade can restore it later.)

## Decision 4 — native side (Swift 6 / macOS 26.2)

`NativeFetchProxy` is an **`actor`** (not `@MainActor`) owning one `URLSession` with a
**dedicated `HTTPCookieStorage`** (the extension's own Proton session, isolated from
`URLSession.shared`). `@MainActor MessageBroker.fetchProxy(env)` validates scope on the
main actor, then `await`s the proxy actor (network off the main actor). Redirect
containment via a `URLSessionTaskDelegate`. `AbortSignal` → a `__fetch/abort` call cancels
the task.

## Decision 5 — cookies side-step Decision 4

Native `URLSession` cookies live in `HTTPCookieStorage`, distinct from both WK data
stores. The fork *selector* is precisely the mechanism to transfer session state WITHOUT
sharing cookies (account tab = web session in WK store; extension = its OWN session via
the fork endpoint). So `credentials:"include"` wants the extension's native jar —
consistent, no cross-tab leakage, invisible to JS (workers have no `document.cookie`).
This removes the Decision-4 coupling on the fetch path.
