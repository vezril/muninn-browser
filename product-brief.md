# Muninn — Product Brief

*Analysis-phase artifact, 2026-07-11. Feeds the Planning phase (PRD). Owner: Calvin Ference.*

## Vision

A privacy-first, Apple-native macOS browser with a calm, fully custom (Arc-like) shell, built around Proton Pass as its password manager. Muninn knows everything about your browsing and tells no one — Odin's raven, reporting only to you.

## Owner / primary user

Calvin — developer (Scala), privacy-conscious Proton user (`@proton.me`), deep in the Apple ecosystem (MacBook, iPhone, iPad, Apple Watch). First user is the builder; design for personal daily-driver quality first, general audience later.

## Jobs to be done

1. Browse with a shell that stays out of the way (custom, minimal, Arc-like — this is a hard requirement; it drove the engine decision).
2. Log in everywhere with Proton Pass: field icon, dropdown, autofill, save-login — at parity with Pass-in-Safari.
3. Unlock the vault the Apple way: Touch ID / Apple Watch double-tap.
4. Keep browsing private: no engine phone-home, content blocking, no third-party telemetry.
5. (Later) Sync tabs/history across devices via an owner-controlled Scala service — the Safari-exclusive features (iCloud Tabs etc.) replaced with Proton-flavored equivalents.

## What is already decided

See `decisions.md` — name (Muninn), engine (WKWebView + Pass shim), language split (Swift shell / Scala sync), fallbacks. Do not reopen without new evidence.

## What the research established (read before the PRD)

- `research/spike-a-results.md` — why not Chromium: full findings, evidence, and the reusable technique (CRX public-key pinning for canonical extension ID) if fallback (3) is ever exercised.
- `research/spike-b-proton-pass-api-inventory.md` — the shim spec: Proton's Safari manifest is the target profile (~10 namespaces, ~45 methods/events). Tier 1 = trivial stubs (~80% of call sites), Tier 2 = 4 real subsystems (background host, custom-scheme handler, content-world injection + frame registry, message broker), Tier 3 = skip (Proton's Safari build already excludes `webRequest`, `offscreen`, `privacy`, `commands`).
- **Ordered risks to burn down first** (from Spike B, unchanged): (1) auth-fork login flow via `onMessageExternal` bridge on `*.proton.me`; (2) dropdown-iframe mechanics on strict-CSP sites; (3) service-worker global-scope assumptions in `background.js`.
- Spike B's inventory was taken 2026-07-11 against Pass v1.38.2 — **re-run the 5-minute grep inventory before implementation starts**; Proton ships extension updates frequently.

## Proposed MVP (walking skeleton)

One window, one tab, WKWebView, plus the shim runtime: **log in at account.proton.me → vault unlocks → autofill completes on one real site**. That is the smallest end-to-end proof that retires risks 1–3. Spike B's estimate: ~4–8 focused weekends for this skeleton in Swift.

Explicit non-goals for MVP: tab strip/shell polish, sync layer, content blocking, save-login prompt, iOS.

## Success metrics (draft — sharpen in PRD)

- Walking skeleton: the three risk flows pass on the real Proton production extension bundle.
- Daily-driver bar: Calvin uses Muninn as default browser for a full week without reaching for Safari for a Pass-related reason.
- Privacy bar: egress audit shows only user-initiated + allowlisted hosts (see follow-up in spike-a-results.md).

## Constraints & standing rules

- **Never handle Proton credentials** — all login/unlock actions are performed by the human at explicit gates; no logs/screenshots capturing vault data.
- **Warn Calvin in chat before launching anything that opens GUI windows** — he works on this Mac and closes stray windows (this killed three test runs in Spike A).
- Pass shim tracks Proton's Safari build as its canary on each Pass release.
- macOS-first; iOS is a strategic option later (WKWebView work transfers directly).

## Open questions for the PRD phase

1. Shell scope for v0.x after the skeleton: what is the minimal tab model worth building before daily-driving?
2. Save-login (1.6) parity: Safari profile lacks `webRequest` — accept Proton's degraded heuristics or build a native heuristic?
3. Sync layer protocol/hosting (self-hosted Scala service? Proton Drive-backed?) — defer architecture until the skeleton ships?
4. Content blocking: WKContentRuleList source lists (EasyList? curated?) and update mechanism.
5. Distribution: signed + notarized direct download vs Mac App Store (App Store sandbox may constrain the shim and default-browser status — investigate during architecture).
