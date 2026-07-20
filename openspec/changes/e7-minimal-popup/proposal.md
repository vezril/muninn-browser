# Proposal: e7-minimal-popup

## Why

E6's definitive root cause (`research/e6-external-gate-2026-07-17.md`): the auth-fork
login is **initiated by the popup**. Proton's `popup.js` "Sign in" generates the fork
key/state, writes `storage.session["f"+state]`, and opens the fork URL; `background.js`
only *reads* `f<state>` on consume. Our `onInstalled → onboarding` path never initiates a
fork, so consume throws "Invalid fork state". **Login cannot complete without the popup's
fork-initiation** — which is also the daily-driver sign-in UX Calvin wants.

## What

A **minimal Pass toolbar popup**: render the vendored `popup.html`/`popup.js` in a visible
`WKWebView` (served via the existing `muninn-ext://` scheme handler), with the shim
(`chrome`/`browser`) injected into the popup page's MAIN world (it is a TRUSTED extension
page — unlike web pages, MAIN-world shim is correct here) and wired to the `MessageBroker`
as a new `popup` context. The user clicks "Sign in" → Proton's own `popup.js` runs the
real fork-initiation → login completes the correct way.

Storage is shared through the broker's single `ExtensionStorage`, so the popup's
`storage.session["f"+state]` is exactly what `background.js`'s consume reads back.

## MVP cutline

Enough to complete sign-in: popup renders, its `browser.*` calls route (storage, runtime
messaging to background, tabs/windows for the fork URL), and "Sign in" initiates the fork.
Full popup features (vault list, item UI, autofill triggers) are E7-proper / later.

## Open risk

`popup.js` likely uses `runtime.connect` **ports** to sync auth state with `background.js`
(we deferred ports, Decision 4b). If the popup needs a live port to render/sign-in, this
change also implements **minimal cross-context ports** (popup↔background) on the existing
bus. Assess early (does the "Sign in" path need the port, or just storage + navigate?).

## Impact

Completes E6 login. New: `PopupHost` + a `popup` broker context + (likely) cross-context
ports. Reuses `ExtensionSchemeHandler`, `content-polyfill` shim, and the E6 bus.
