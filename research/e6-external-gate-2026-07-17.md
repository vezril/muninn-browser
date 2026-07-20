# E6 gate — externally_connectable bridge live-inspected; bridge installs, handshake still incomplete

**Date:** 2026-07-17 (Calvin at the keyboard, live Web Inspector; no credentials — the
page never advanced past the pre-login "missing permissions" screen). Ground rules 1+2 held.
**Build:** `feat/e6-externally-connectable`, gate mode (`MUNINN_E6_GATE=1`, `isInspectable`
enabled on both webviews for this supervised session only).

## What was verified live

Boot + fork fire correctly (background-loaded, correct onboarding URL, relay traffic).
Then, via Safari Web Inspector on the **account.proton.me** onboarding page's MAIN world:

```
{"host":"account.proton.me","chrome":"object","sendMessage":"function",
 "id":"ghmbeldphafepmbegfdlkpapadhbakde","browser":"object"}
```

**So the externally_connectable bridge IS installed on the live page** — `window.chrome`
exists, `chrome.runtime.sendMessage` is a function, `chrome.runtime.id` is the canonical
id, `window.browser` is set. The earlier "ReferenceError: can't find variable chrome"
readings were the inspector's execution-context selector pointing at the WRONG page/frame
(the `muninn-ext://<id>` background host page, or a subframe) — not the account MAIN world.

## What still fails

1. The account app's own `onboarding.js:466` throws **`TypeError: undefined is not an
   object (evaluating 't4.runtime')`** — its internal browser-API reference (`t4`) is
   undefined when used. This is the account app's webextension-polyfill failing to
   capture the API.
2. Manually sending the real detection messages
   (`chrome.runtime.sendMessage(id, {type:'pass-installed'|'pass-onboarding'|'auth-ext'})`)
   produced **no `MUNINN` output** — the round-trip did not visibly resolve/reject. Could
   not be pinned down: the inspector console context kept flipping between frames/worlds
   across reloads (chrome present in one eval, ReferenceError the next), making manual
   console probing unreliable.

## The account↔extension handshake (decoded from background.js)

Message-type enum (`rf`): `ACCOUNT_PROBE="pass-installed"`, `ACCOUNT_ONBOARDING="pass-onboarding"`,
`ACCOUNT_EXTENSION="auth-ext"`, `ACCOUNT_FORK="fork"`. `lU.allowExternal` = those four.
Handlers:
- `pass-installed` → `() => true` (pure presence check)
- `pass-onboarding` → `(e,{tab:t}) => !!t?.id && h(t.id)` (needs the sender's `tab.id`)
- `auth-ext` → needs `authStore.hasSession()` (post-login only)

Permission state is background-internal: `J.permissionsGranted = await permissions.contains(
{origins: host_permissions})`; broadcast as `PERMISSIONS_UPDATE`. Our worker returns
`permissions.contains → true` (verified in `PermissionsProbeTests`), so background should
compute `granted = true`.

## Leading hypotheses for the next session (in priority order)

1. **We set `window.browser` as well as `window.chrome`.** Real Chrome exposes ONLY
   `window.chrome` to externally_connectable pages. Proton's account app uses the Mozilla
   webextension-polyfill, which branches on whether `window.browser` already exists —
   our minimal `window.browser = {runtime:{…}}` may send it down the "native Firefox
   browser" path and then break (`t4.runtime` undefined). **Fix to try first: expose only
   `window.chrome` (drop `window.browser`), matching Chrome; let the app's polyfill wrap
   chrome itself.**
2. **Live round-trip completion.** Confirm (programmatically, not via the flaky console)
   that MAIN → `window.postMessage` → isolated listener → native `__externalMessage` →
   `onMessageExternal` actually completes on the real page. Add gate instrumentation that
   logs the external message `type` (a safe discriminator, not payload) and whether the
   response returns — instead of manual console probing.
3. **Timing.** If `t4` is captured before our `document_start` bridge sets `window.chrome`,
   the app caches undefined. Verify our MAIN-world user script truly runs before
   `onboarding.js` (it should, per WebKit's document_start guarantee).

## Status (at gate 4)

Bridge is confirmed present and correctly shaped on the live account page — a real step
past the previous gate. The remaining gap is the account app's API capture / round-trip,
narrowed to the three hypotheses above. NOT D4. Next step is code (hypothesis 1) + a
reliable programmatic gate signal (hypothesis 2), not more manual console inspection.

---

## RESOLUTION — gates 5 & 6 (2026-07-18): "missing permissions" CLEARED

Two fixes, both validated live via the programmatic gate signal (payload-free —
message `type` + round-trip completion only):

1. **Hypothesis 1 confirmed — drop `window.browser`.** `externally-connectable.js` now
   exposes ONLY `window.chrome`. Proton's account app uses the Mozilla
   webextension-polyfill, which wraps `chrome` into a promisified `browser` only when
   `window.browser` is undefined. Our pre-set minimal `window.browser` made it skip
   wrapping and use the incomplete object → `t4.runtime` undefined. Dropping it fixed the
   error, and the account app began **sending `pass-installed`** through the bridge.
   - Gate 5 log: `ext-msg type=pass-installed … → sent` (but not RESPONDED).

2. **`fireMessage` now supports Promise-returning listeners.** The worker onMessage
   delivery only handled `sendResponse` + `return true`; Proton's `lU.onMessage` is
   async (returns a Promise), so its response was dropped and we sent `null`. Now a
   thenable return resolves to the response.
   - Gate 6 log: `ext-msg type=pass-installed … → RESPONDED`.
   - **UI advanced past "missing permissions" to "Welcome to your new password manager."**

The detection/permission barrier that blocked E6 across four gates is **RETIRED**.
Tests: `E6ExternalConnectableTests.testExternalMessagePromiseReturningListener` (green).

## NEXT BLOCKER — the auth-fork session handoff (gate 6, deeper)

Proceeding into sign-in, the account app sent the actual **`fork`** message
(ACCOUNT_FORK) — and it **RESPONDED** (`ext-msg type=fork … → RESPONDED`), so the fork
handler in `background.js` ran. But the UI then showed **"Unable to Sign In to Proton
Pass. Unknown error occurred."** So we are now at the **session-fork completion** step
(Spike B Risk 1's core), past detection.

**ROOT CAUSE CONFIRMED (2026-07-18) — it is CORS, NOT Decision 4.** The fork handler
consumes the fork via `fetch("https://pass.proton.me/api/...", {credentials:"include"})`
(a GET on `.../sessions/forks/{selector}`; `API_URL = "https://pass.proton.me/api"`). The
background worker's origin is `muninn-ext://<id>` (custom scheme), so this cross-origin
fetch is **CORS-blocked**. Verified headlessly (`ForkCorsProbeTests`, net-gated): the same
fetch fails with **`TypeError: Load failed`** — WebKit's CORS-blocked signature. In a real
browser the extension's `host_permissions` (`*://*/*`) grant CORS-bypass network
privilege; a WKWebView custom-scheme origin gets none. The earlier Decision-4 (cookie
store) hypothesis is **superseded** — the request never completes the CORS preflight/check,
so cookies aren't even reached.

**Fix: a native fetch proxy.** The extension needs its `host_permissions`-scoped network
requests routed through native (URLSession, no CORS), matching real-browser extension
privilege. Design in progress (webkit-developer agent): override the worker's `fetch` to
route `*.proton.me` requests through the broker → native URLSession → response, scoped to
manifest host_permissions (the page must NOT get an open proxy). This also side-steps
Decision 4: cookies move to native URLSession storage for the fork consume. Ground rule 1
throughout: never capture the fork payload, selector, session tokens, or credentials — the
gate log and probe stay type-only / unauthenticated.

**Likely its own change/epic** (native extension networking; relates to ADR-002 proxy
routing / E8). The minimal viable slice for the walking skeleton: `GET` JSON requests to
the Proton API with a few headers + `credentials:"include"` cookie handling.

NOT D4-the-decision-to-abandon: engine, boot, injection, bus, frame registry,
externally_connectable detection, and now the fork message delivery ALL work live. The
remaining work is the session handoff topology.
