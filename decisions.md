# Muninn — Locked Decisions

Decisions made by Calvin Ference during spike review, 2026-07-11. These are settled; do not re-litigate them without new evidence.

## D1 — Product name: **Muninn**

Odin's raven "Memory" — flies across all the worlds each day and reports back *only to Odin*. Your raven, roaming the web, reporting only to you.

Availability sweep (2026-07-11, search + RDAP + iTunes Search API + Justia; not legal clearance):

- **Trademark:** no standalone "Muninn" mark found (USPTO via Justia, EUIPO quick search). Only composite: "HUGINN & MUNINN PUBLISHING" (education/publishing classes — non-blocking).
- **App Store:** no browser/security apps named Muninn; only small indie apps (language-learning, games). Ship as **"Muninn Browser"** for the store listing.
- **Known neighbor:** Munin (one N), the open-source monitoring tool — no legal concern, minor dev-mindshare collision. Accepted.
- **Domains:** `muninn.com`/`.io`/`.app`/`getmuninn.com` registered by third parties; `muninnbrowser.com` and `muninnbrowser.app` were **available** at sweep time. Registering them is a pending human action.
- **TODO (human):** trademark-attorney clearance before public launch; register defensive domains.

## D2 — Engine: **Path 2 — WKWebView (Apple WebKit) + Proton Pass API shim**

Basis (see `research/spike-a-results.md`, signed off 2026-07-11):

- Spike A: CEF hosts Proton Pass fully **only** in Chrome-style windows (T1 ✔ T2 ✘ T3 ✘). A custom Arc-like shell cannot host the extension on embedded Chromium today — extension-page hosting breaks under Alloy style and crashes under JCEF.
- Spike B: the shim is bounded — Proton's own Safari build profile is the spec (~10 namespaces, ~45 methods; `webRequest`/`offscreen` excluded by Proton themselves).
- Privacy: Chromium ships default-on Google service traffic (GCM registration attempts observed in our own logs); WebKit posture preferred by owner.
- Apple ecosystem: passkeys/iCloud Keychain via ASAuthorization, Touch ID + **Apple Watch** vault unlock via LocalAuthentication, Handoff, Apple Pay JS, WKContentRuleList blocking, battery efficiency on Apple Silicon.
- Validated by owner experience: Proton Pass works well in Safari (same engine, same degraded API profile).

Consequences: no extension platform — Pass support is a purpose-built shim (Spike B Tier 1+2). JCEF/Chromium ruled out for the engine layer entirely.

## D3 — Language split

- **Shell + engine integration: Swift/AppKit** (WKWebView, WKContentWorld, WKURLSchemeHandler, NSPopover, LocalAuthentication). The native layer is unavoidable and owns the shim runtime.
- **Sync/service layer: Scala** (Calvin's stack) — history/tab sync, any server-side or cross-device logic. Spike A's Test 3 disqualified the JVM from the *engine* layer only.

## D4 — Fallback lines (if the shim hits a wall)

Ordered: (1) fix within shim scope — Proton's Safari build proves the profile suffices; (2) Pass web app in a pinned tab; (3) Chrome-style CEF window (last resort — surrenders the custom shell).
