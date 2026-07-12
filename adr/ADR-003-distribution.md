# ADR-003 — Distribution: Unsigned Personal Builds for v0.x, MAS Preconditioned on Proton Authorization

**Status:** Accepted — Calvin Ference, 2026-07-11 22:55 EDT (architecture.md §10)
**Date:** 2026-07-11
**Source IDs:** OQ-5, AS-7, FR-29, D1, E12
**Evidence:** `openspec/changes/architecture-and-adrs/research/2.2-sandbox-distribution.md`

## Context

The approved PRD resolves OQ-5 as "signed + notarized direct download for v0.x; revisit Mac App Store at 1.0," flagging the sandbox investigation to this phase. Research findings: the shim techniques (WKURLSchemeHandler, hidden WKWebView, content worlds) survive App Sandbox technically; default-browser eligibility on macOS is an Info.plist declaration available to every distribution channel; the real MAS blocker is App Review guidelines 5.2.1/5.2.2 (embedding a third party's branded extension, with authorization demandable on request) — and no extension-supporting browser exists on the macOS App Store (Orion, the closest analog, deliberately ships direct-download). Separately verified: Gatekeeper only evaluates quarantined (downloaded) apps; locally built, ad-hoc-signed apps run without any Apple Developer Program membership. **Calvin's enrollment is currently lapsed** (confirmed 2026-07-11, task 2.4).

## Decision

1. **v0.x (M0–M2): unsigned/ad-hoc-signed local builds.** Xcode's "Sign to Run Locally" (or a free Personal Team) suffices for the app to run, be set as default browser (FR-29), and use every needed capability on Calvin's own Mac. **No Developer Program renewal needed for anything before external distribution.**
2. **First distribution beyond Calvin's machine: Developer ID + notarization.** Renewal of the lapsed enrollment (~US$99/yr) becomes the prerequisite at that moment, not before. Hardened runtime is expected to be clean for the shim because the background host is a WKWebView, not an in-process JSContext (ADR-005) — no `allow-jit` entitlement anticipated.
3. **Mac App Store revisit at 1.0 carries an explicit precondition: written authorization from Proton (or a partnership)** covering guideline 5.2.1 (trademark/IP in the embedded bundle) and 5.2.2 (service-access authorization on demand). Without it, the revisit clause is a dead letter and MAS is off the table. The GPLv3 source-build path (ADR-001 point 3) additionally becomes the mandatory bundle origin for any public distribution.

## Consequences

- Nothing blocks M0–M2 on Apple paperwork; the lapsed enrollment is recorded (AS-7) and parked until an actual distribution event.
- The PRD's OQ-5 resolution stands, refined: "signed + notarized" is deferred from v0.x-as-written to first-external-distribution, since v0.x has a sole user on one machine (PRD §2 scope; AS-6 covers the single-machine premise). This is a narrowing, not a contradiction, of the approved text — flagged for Calvin at the architecture gate (architecture §10 item 1).
- Sandbox adoption is decoupled from MAS: Muninn may voluntarily adopt App Sandbox later for defense in depth, but no M0–M2 requirement forces it, and nothing in the shim architecture forecloses it (research 2.2 §1).
- D1's pending trademark-counsel TODO gains urgency only at public distribution — same trigger as the enrollment renewal; both belong to E12.
