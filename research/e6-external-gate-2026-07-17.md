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

---

## DEFINITIVE ROOT CAUSE (2026-07-20, gate 9 + static) — login needs the popup's fork-initiation

Gate 9 (safe fetch-entry probe): the fork consume makes ZERO worker network calls and
`fork → RESPONDED` with a CAUGHT error. Static trace of the consume handler `_`:

```js
_ = async ({service:e}, {payload:a}, {tab:r}) => {
  let i = `f${a.state}`;
  let s = await e.storage.session.getItem(i).catch(()=>null);   // read stored fork state
  if (!a.keyPassword) throw Error("Invalid `ExtensionForkPayload`");
  await I.consumeFork({mode:"extension", tabId:r?.id, localState:s, ...a}, `${SSO_URL}/api`)
  // consumeFork → throws cX("Invalid fork state") unless (localState!==null && key) && selector && state
}
```

The `f<state>` **write** is NOT in background.js — it's in **`popup.js`** (also `dropdown.js`,
`settings.js`):

```js
await storage.session.set({[`f${state}`]: JSON.stringify(forkState)});  // popup.js fork-init
window.location.replace(forkURL);
```

So the auth-fork is **initiated by the popup's "Sign in"**: the popup generates the fork
state/key, stores it in `storage.session["f"+state]`, and navigates to the fork URL. The
account login then forks and sends the extension the `fork` message; the consume reads
`f<state>` back. **Our `onInstalled → tabs.create(onboarding)` flow never runs that
fork-init**, so `f<state>` is absent → "Invalid fork state" → "Unknown error".

**Conclusion:** login cannot complete via the onboarding page alone. It requires the
extension to INITIATE the fork (popup behavior). This couples E6's login completion to
**E7 (popup)** — or to a minimal fork-init shim that replicates popup.js's
`storage.session.set({f<state>}) + open fork URL`.

**NOT abandon-D4** — detection, bus, injection, and the fetch proxy all work; the gap is
that nothing initiates the fork. The onboarding path was a detour; the real sign-in is
popup-driven (which is also the daily-driver UX).

---

## GATE 10 (2026-07-22) — unified root cause: background auth service uninitialized

Six live sign-in gates (Calvin at keyboard; ground rule 1 held — the fork-gate log is
tag/HIT-MISS/keys-only, never values). Instrumented (all behind `MUNINN_FORKGATE`):
storage session `f<state>` store/get (SHA tag + HIT/MISS + localState empty?), the
`onMessageExternal` fork relay (payload KEY NAMES only), the native fetch proxy
(`/sessions/forks` path with selector REDACTED + status), and the worker fetch **probe**
(host only, fires before the allowlist on every worker `fetch`).

**Findings (each confirmed live):**
1. **State plumbing WORKS.** `consume get fork tag=X -> HIT` — `payload.state` matches a
   stored `f<state>`. The old "state mismatch" hypothesis is refuted for this path.
2. **`localState` is a red herring.** `uh` validates
   `("extension"===mode || (localState && key)) && selector && state`. Mode IS "extension",
   so the localState/key clause short-circuits. Our `"{}"` never mattered.
3. **The fork payload is COMPLETE.** relay log:
   `payloadKeys=[keyPassword,offlineKey,persistent,selector,state,trusted]`. So `selector`
   and `state` are both present → `uh` should PASS.
4. **The pullFork fetch NEVER FIRES.** After the consume HIT, there is **no worker fetch
   probe** at all. The only probe in the whole run is host=`<extension-id>` (a boot-time
   request to a relative URL, resolved against the worker origin `muninn-ext://<id>`).
   So `consumeFork` throws AFTER reading `f<state>` but BEFORE any network call.

**Root cause (unified with the popup blank):** the background's **auth service / API client
is never initialized** in our flow. `consumeFork → uy → uh` uses the auth service's API
client (`t`/`e.api`); uninitialized, its base URL is empty (hence the one boot request going
to the extension origin, not `account.proton.me`), so the pull throws before fetching. This
is the SAME uninitialized-auth-service state the popup waits on (E7 "app-root empty"). One
blocker, two symptoms.

**Next step (the real one now):** initialize the background auth service so its API client is
configured (base = SSO_URL). In the real extension the popup sends **`AUTH_INIT`** on open
(handler `S = async (e,{options}) => (options.forceLock=…, await e.service.auth.init(options), e.getState())`).
Our fork-init flow never sends it. Try: send `AUTH_INIT` to the background before the fork
consume (decode the options the popup sends), then re-gate — expect the pullFork to fire
(worker probe host=account.proton.me → proxy `/sessions/forks/<redacted>` → status). If
`auth.init` needs a session we don't have yet, that's the chicken/egg to solve (it likely
inits the client pre-session for exactly the fork flow). Fork-gate instrumentation is in
place (behind `MUNINN_FORKGATE`) for the next run.

## GATE 11–13 (2026-07-22) — root cause CONFIRMED: API client undefined (auth service uninit)

Added credential-safe capture: worker error hook (console.error / error / unhandledrejection →
native, truncated), and the consume RESPONSE at the relay (token-runs redacted). Results:
- **No worker error surfaced** — Proton's message framework catches the throw internally.
- **Consume response** = `{type:error, payload:{title:"Something went wrong",
  message:"Unable to sign in to Proton Pass. Unknown error occurred"}}` — the handler `_` does
  `catch(e){throw ub(ug.ERROR,e)}`, and `ub` maps ANY error to that CANNED message, discarding `e`.
- Full consume handler `_`: getItem `f<state>` (HIT) → `keyPassword` present → `I.consumeFork(...)`
  → **throws before any fetch** (no worker fetch probe for account.proton.me post-consume).

`consumeFork → uy → uh` calls `(e.pullFork ?? (({selector})=>{…; r(t)}))(t)` where `r` is the API
client. The API client is **undefined** (auth service not initialized), so `r(t)` throws a TypeError
before the network call. Canned-error mapping hides it. This is the SAME uninitialized-auth-service
state that leaves the E7 popup blank.

**Verdict:** the remaining work is E7-scale — initialize the background auth service so its API
client (base = SSO_URL) exists, which unblocks BOTH the fork consume AND the popup render. This is
NOT a quick patch: `auth.init` (AUTH_INIT handler `S`) likely pulls in the crypto worker + session
bootstrap. Gates were paused here (13 total; Calvin's login fatigue) — resume as focused heads-down
auth-service-init work with a SINGLE verification gate, not incremental diagnostic gates.

All fork-gate instrumentation remains behind `MUNINN_FORKGATE` (dormant in normal use).

## GATE 14–15 (2026-07-22) — fix attempt failed; consume still throws pre-fetch; error unreachable

Broadened the worker capture to console error/warn/info + auth/fork-tagged logs (redacted):
**zero** worker log lines — Proton's production logger (`nc.*`) is a no-op, nothing hits console.
So the actual exception is unreachable via instrumentation (canned response + silent logger).

Static find: `consumeFork` calls `onForkConsumeStart:async()=>{if(ta.hasSession())throw ub(ug.CONFLICT);…}`
BEFORE the pull — throws if the auth store already has a session. Hypothesis: a stale persisted
session (`ps` in `storage.local.enc`, which MUNINN_FRESH did NOT clear) → hasSession() true → CONFLICT.
**Fix applied:** ExtensionStorage.init drops storage.local.enc under MUNINN_FRESH. **Gate 15 result:
still no fetch after consume** → CONFLICT was NOT the cause (or hasSession() is set some other way).

So the throw is in the pull path (`uy → uh → (e.pullFork ?? default)(t)`; auth service `pullFork = gy`)
and fires synchronously before any `self.fetch` (no worker probe post-consume). Next real lead:
trace `gy` (the auth service pullFork) and the api client `t`; but the definitive unblock is the
**exact exception + stack**, which needs a **Web Inspector session on the background host worker**
(MUNINN_E6_GATE enables `isInspectable`) — set a breakpoint at the consume catch / pullFork and read
the real error. 15 gates done; guess-and-gate has stopped converging. Do the inspector read (or more
static `gy` tracing) BEFORE the next fix attempt.
