# Tasks: architecture-and-adrs

## 1. Pre-gate check

- [x] 1.1 Confirm Calvin's PRD/roadmap verdicts are recorded in `prd.md` §13 and `roadmap.md` §6 (drafting may start before this, but flag loudly in every session until recorded)
  — Done 2026-07-11 21:14 EDT: both verdicts **"Approve"**, recorded verbatim in `prd.md` §13 and `roadmap.md` §6; headers flipped to APPROVED; `CLAUDE.md` state updated.

## 2. Desk research (feeds the deferred-question ADRs)

- [x] 2.1 Research Pass extension bundle acquisition options (store download vs. `WebClients` build vs. vendored copy) — document evidence for the AS-8 ADR
  — Done 2026-07-11: evidence in `research/2.1-bundle-acquisition.md`. Recommendation: extract Safari-target bundle from the locally-installed Proton Pass for Safari.app (has `fork.js` → dissolves the hand-written auth bridge), vendor with hash lockfile, pinned-tag source build as escape hatch. 4 spike candidates flagged (S1–S4).
- [x] 2.2 Research App Store sandbox constraints vs. shim techniques (WKURLSchemeHandler, hidden WKWebView, default-browser status) — evidence for the OQ-5 distribution ADR
  — Done 2026-07-11: evidence in `research/2.2-sandbox-distribution.md`. OQ-5's direct-download resolution confirmed and strengthened (MAS killer = guideline 5.2.1/5.2.2 Proton IP, not the sandbox; zero MAS extension-browser precedent). Bonus: v0.x personal builds need NO Apple Developer membership; prefer hidden-WKWebView host over JSContext to avoid the allow-jit entitlement.
- [x] 2.3 Decide egress-audit tooling shape (throwaway mitmproxy config vs. reusable harness) — evidence for the NFR-5 ADR
  — Done 2026-07-11: evidence in `research/2.3-egress-audit-tooling.md`. Recommendation: reusable `audit/` harness — pktap (`tcpdump -k`, `eproc` delegation) for attribution + per-`WKWebsiteDataStore` `proxyConfigurations` port routing for classification; NO TLS interception anywhere (credential rule satisfied by construction). One load-bearing fact needs a ½-day spike: `eproc` attribution for WebKit.Networking on macOS 26.
- [x] 2.4 Confirm Apple Developer Program enrollment status with Calvin (AS-7) — one question, affects distribution ADR consequences
  — Answer (Calvin, 2026-07-11): **No / lapsed enrollment.** The distribution ADR must record enrollment as a pending human action before any M3 signing/notarization work; nothing before M3 is affected.

## 3. Draft the HLD

- [x] 3.1 Draft `architecture.md` via solution-architect: driving characteristics from NFR-1…10, style choice + trade-offs, component boundaries (shell + 4 Tier-2 subsystems), Mermaid C4 context + container diagrams, risk analysis keyed to Spike B's 3 risks
  — Done 2026-07-11: `architecture.md` v0.1 PROPOSED. Style: single-quantum modular monolith / closed microkernel (one vendored plug-in). Risk 1 downgraded per research 2.1 (fork.js); 9-row risk table; decisions index ADR-001…008.
- [x] 3.2 Verify scope boundary: sync appears only as a labeled extension point; no M3-only design beyond extension points
  — Done 2026-07-11: mechanical grep — sync/Scala only in provenance, quanta note, and §9 extension points; M3 terms only in context-diagram labels + §9. No protocol/hosting design present.

## 4. Draft the ADRs

- [x] 4.1 Write ADR-001…004 for the deferred questions: bundle acquisition (AS-8), egress-audit tooling (NFR-5), distribution/sandbox (OQ-5), FR-24 test approach — status `Proposed`, or `Proposed (needs spike)` with the spike named
  — Done 2026-07-11: `adr/ADR-001…004`. ADR-002 is `Proposed (needs spike — S5: eproc attribution)`; others `Proposed`.
- [x] 4.2 Write ADR-005…008 for core choices: background-host substrate (WKWebView vs. JSContext), custom URL scheme design, message-broker contract, canonical-ID presentation (FR-13)
  — Done 2026-07-11: `adr/ADR-005…008`. Hidden WKWebView host; `muninn-ext://<canonical-id>/` scheme with manifest-derived WAR allowlist; versioned opaque-payload broker envelope; canonical ID always presented.

## 5. Review gates (maker-checker + mechanical)

- [x] 5.1 Run mechanical traceability script: every FR/NFR/AS/OQ/D/E reference in `architecture.md` + `adr/*.md` resolves against `prd.md`/`roadmap.md`/`decisions.md`; ≥1 reference per ADR; all four Nygard sections non-empty per ADR
  — Done 2026-07-11: PASS (8 ADR files; zero unresolved references; all sections non-empty; all statuses Proposed).
- [x] 5.2 Separate reviewer agent critiques the HLD + ADRs against PRD/spikes/decisions (refute-oriented); fix blocking findings, bounded ~3 iterations
  — Done 2026-07-11: verdict CONCERNS, 6 blocking findings, all fixed in 1 iteration (NFR-6 citation; FR-12 promotion + FR-13 mechanism supersession now flagged as gate deviations in §10; S5 scope expanded to proxy-routing verification; App Nap mechanism corrected to process-level assertion + hidden-page timer throttling added to E3 scope; ADR-006 initiator-identification gap named as load-bearing, spike S6 created). Non-blocking fixes applied too. Traceability gate re-run: PASS.
- [x] 5.3 Check no ADR contradicts D1–D4 and none encodes Pass API detail tighter than Spike B's Safari-profile table
  — Done 2026-07-11: reviewer confirmed zero D1–D4 contradictions; one API-tightness violation found (ADR-007 asserting Pass's lastError handling as fact) and softened to spike-gated expected behavior.

## 6. Human gate and closeout

- [x] 6.1 Present to Calvin; record his verbatim verdict + timestamp in `architecture.md`
  — Done 2026-07-11 22:55 EDT: verdict **"Approve"** recorded in §10, ratifying the three flagged deviations (distribution narrowing, FR-12 promotion, FR-13 mechanism swap).
- [x] 6.2 On approval: flip accepted ADR statuses to `Accepted` in the same commit; update `CLAUDE.md` artifact state (Solutioning: architecture done, next per-epic changes starting with E1)
  — Done: ADR-001/003/004/005/007/008 → Accepted; ADR-002/006 → Accepted (needs spike S5/S6); CLAUDE.md updated (next: per-epic changes, E1 first).
- [ ] 6.3 Ship via `/git-ship` (PR-gated main)
