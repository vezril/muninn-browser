# E5 task-1 live gate — orchestrator.js injected, "missing permissions" persists; bus works live

**Date:** 2026-07-17 (Calvin at the keyboard; no credentials touched — ground rule 1)
**Build:** `feat/e5-injection-frame-registry-wip` merged to `main` (PR #13), Debug, gate mode
(`MUNINN_E6_GATE=1`).
**Ground rule 1:** gate log is payload-free (direction + sender host + timing only). No
message bodies, tokens, or vault data captured; no screenshots of credential fields.

## What was tested

The E5 checkpoint hypothesis (tasks.md task 1): does injecting `orchestrator.js` (the
general content script, isolated world, `document_end`, all frames) clear the account
app's **"Proton Pass is missing permissions"** onboarding error that blocked E6?

The full FR-9 injection set is now live on every http(s) page:
bootstrap (id+manifest) → `content-polyfill.js` (isolated, `document_start`) →
`orchestrator.js` (isolated, `document_end`) → `webauthn.js` (MAIN, `document_start`);
`fork.js` nav-gated to `account.proton.me`. Verified present in the built bundle.

## Result: RANK-2 — necessary groundwork, but does NOT clear the gate

The onboarding page loaded with the **correct fork params**
(`.../pass/extension-onboarding?loginParams=app%3Dproton-pass-extension%26state%3D<nonce>`),
and the **"Proton Pass is missing permissions"** banner **still appears**.

### But the cross-context bus works LIVE (new, and significant)

Gate log (payload-free), nine round trips in ~7s:

```
E6-GATE background-loaded
E6-GATE open-url create -> account.proton.me/pass/extension-onboarding
E6-GATE relay-in  from account.proton.me   ┐
E6-GATE response-out from account.proton.me ┘  ×9 pairs
```

- `background.js` boots, fires `onInstalled`, opens the correct fork URL via `tabs.create`.
- The **real account onboarding page** drives `runtime.sendMessage` across the context
  boundary to the host worker's `onMessage`, and `sendResponse` correlates back — nine
  times. **The E6 message bus carries real Proton traffic end-to-end.** First live proof.

So "missing permissions" is **not** a severed connection. The isolated-world content
script (orchestrator/fork) reaches `background.js` and gets responses.

## Root cause (sharpened): the check is in the MAIN world, via `externally_connectable`

`vendor/pass-extension/1.38.0/manifest.json`:

```json
"externally_connectable": { "matches": [
  "https://account.proton.me/*", "https://pass.proton.me/*" ] }
```

`externally_connectable` is Chrome's **page→extension** channel: the web app, running in
the page **MAIN world**, calls `chrome.runtime.sendMessage(EXTENSION_ID, …)` (and/or
`connect`) and it routes to the extension's `onMessageExternal`. A real browser injects a
minimal `chrome.runtime` (`id`/`sendMessage`/`connect`) into the MAIN world **only** on
the externally_connectable-matched origins.

Our design deliberately keeps the page MAIN world **empty** (S2 / ADR-007 isolation —
proven by `ForkBridgeIsolationTests`, still green). So the account app's MAIN-world
`chrome.runtime.sendMessage(extId)` presence-check has nothing to talk to → the extension
reads as absent → **"missing permissions."** This is orthogonal to the isolated-world
orchestrator traffic that is succeeding on the bus.

This **corrects the earlier E6 checkpoint's stated blocker** ("we inject only fork.js, not
orchestrator.js"). Orchestrator is now injected and the isolated bus works; the true
remaining blocker is the **MAIN-world `externally_connectable` bridge**, which is an E6
(auth-fork) concern, not general injection.

## Residual uncertainty (bounded by ground rule 1)

The nine relay-in/response-out pairs are the isolated-world content script's own
extension messaging. Whether any of them is a `window.postMessage`-fallback detection
handshake (fork.js bridging MAIN↔isolated) that `background.js` answered *negatively*
cannot be distinguished from here without logging message **types** — deliberately not
captured this run (payload opacity). The next experiment resolves it directly.

## Next experiment (targeted, cheap) — E6, not E5

Add a **narrow `externally_connectable` MAIN-world bridge**: expose ONLY
`chrome.runtime = { id, sendMessage, connect }` in the page **MAIN world**, scoped to
exactly `account.proton.me` + `pass.proton.me` (the manifest's externally_connectable
matches), routing `sendMessage`/`connect` through the existing cross-context bus to
`background.js`'s **`onMessageExternal`** (the inbound path deferred since E3). Re-run the
gate. Expectation: the presence-check succeeds and the onboarding advances to real login.

This is a **controlled, manifest-justified exception** to MAIN-world isolation — not the
general shim (which stays out of MAIN). It also finally wires the `onMessageExternal`
inbound push path (E3/E5 carry). Scope it as an E6 change (auth-fork detection bridge).

## Verdict

- E5 orchestrator injection: **correct and done** (built, green, live-exercised).
- E6 auth-fork: unblocked one layer deeper — bus proven live; remaining work is the
  externally_connectable MAIN-world detection bridge + `onMessageExternal`.
- No D4: engine, boot, injection, and the bus all work against the real Proton app.
