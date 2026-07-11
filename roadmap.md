# Muninn — Roadmap & Epic Breakdown

**Version:** 0.1 DRAFT
**Date:** 2026-07-11
**Status:** Derived from `prd.md` v0.1 DRAFT — inherits its pending HUMAN GATE. Not independently approved; Calvin's PRD approval and this roadmap's approval are intended to land together or in immediate sequence (see §6).
**Provenance:** Built directly from `prd.md` (post-checker-review revision — all FR/NFR/SM/OQ IDs resolve, MVP cutline = exact P0 set per §9). Consulted for context only, not re-litigated: `product-brief.md`, `decisions.md` (D1–D4 locked), `research/spike-b-proton-pass-api-inventory.md` (Tier 1/2/3 breakdown, 4–8 weekend skeleton estimate), `CLAUDE.md` ground rules. No requirement in this document is invented — every epic traces to an existing `FR-`/`NFR-`/`SM-`/`OQ-` ID. Gaps in PRD coverage are flagged in §5, not silently filled.

**Scope of this document:** roadmap + epic breakdown only. Story files, Given/When/Then acceptance criteria, and OpenSpec delta specs are written later, in Solutioning, per-epic, after the architecture (with its ADRs) exists. Each epic below is written to be story-ready — precise enough that a story-planner can decompose it without re-reading the full PRD.

---

## 1. Milestone Roadmap

| ID | Name | Entry gate | Exit gate (human, with evidence) | FR/NFR set | Est. |
|---|---|---|---|---|---|
| M0 | Foundations | PRD passed checker review (current state) | Calvin approves PRD **and** architecture+ADRs (two human gates, recorded verbatim in `prd.md` §13 / `architecture.md`); dated FR-25 re-grep artifact exists and is triaged; Xcode project builds and runs a blank window on a freshly `git init`'d repo | FR-25, FR-26 (partial) / NFR-6 | ~0.5–1 weekend (excludes review-latency calendar time) |
| M1 | Walking Skeleton (MVP) | M0 exit | Calvin visually confirms UJ-1 end-to-end (login → unlock → autofill) on the production Pass bundle under the **canonical** extension ID; SM-1 holds; NFR-5 and NFR-8 pass; risk-burn order (§9 PRD) was followed, not parallelized | Exactly the §9 P0 set: FR-1,4,5,7,8,9,10,11,13,14,15,19,21,22,25 / NFR-5, NFR-8 gate; NFR-1,2,7 measured-not-gated | 4–8 focused weekends (Spike B estimate) |
| M2 | Daily Driver v0.x | M1 exit | SM-2 holds: Calvin uses Muninn as default browser for a full calendar week without reaching for Safari for a Pass reason, autofill exercised on varied sites, ≤1 crash (NFR-4); latency gates (NFR-1, NFR-7) and NFR-2/3/9/10 now binding, not just measured | The full P1 set: FR-2,3,6,16,17,20,24,26(full),27,28,29 / NFR-1,2,3,4,6,7,9,10 become binding | ~4–6 build weekends + 1 elapsed calendar week (SM-2 itself is not build time) |
| M3 | Hardening & Polish | M2 exit (SM-2 passed) | Opportunistic, per-item review — no single blocking gate (PRD marks P2 "unscheduled"); each shipped item gets its own Calvin sign-off before being considered done | The P2 set: FR-12,18,23; plus OQ-6 investigation, OQ-5 distribution resolution, FR-24's live-merchant Apple Pay verification follow-up | ~2–4 weekends, as-desired, no deadline |
| — | Sync (future horizon) | Explicitly deferred past M2 stability (OQ-3) | N/A — own future PRD/architecture cycle | JTBD-5, out of scope of this PRD entirely | Unscoped |

**Narrative.**

M0 is process, not code: it exists because the pipeline (PRD → architecture → stories) is a discipline, not a formality — the repo is not even `git init`'d yet, and FR-25 is a **hard prerequisite gate**: no shim line gets written before a dated, triaged re-grep artifact exists, per PRD §6.7 and CLAUDE.md.

M1 is the walking skeleton — exactly PRD §9's fifteen P0 FRs, no more, no less, sequenced by the three mandated risks (auth fork → dropdown/CSP → service-worker audit) in that order, not in parallel. This is where D4's fallback ladder gets its first real exercise if risk 1 fails.

M2 is where the PRD's P1 set turns the skeleton into something Calvin can actually live in for a week (SM-2) — tabs, session restore, nav, downloads, default-browser registration, save-login, clipboard, content blocking. The perf/footprint NFRs graduate from "measured" to "gating" here.

M3 is explicitly optional and unscheduled per PRD §8/§9 — passkeys, the app-level biometric gate, the OQ-6 biometric-vault-unlock investigation, and distribution polish. Nothing in M3 blocks daily use; it's picked up opportunistically.

Sync (JTBD-5) is out of scope for this roadmap entirely — OQ-3's resolution is to defer its architecture until v0.x is stable, and it gets its own PRD cycle when that happens.

---

## 2. Epics

Each epic lists: goal, FR/NFR mapping, dependencies, execution-grounded exit criteria, risks, and rough size. IDs are stable (E1…E12) for cross-referencing from later story files.

### E1 — Foundations: Repo Bootstrap, Scaffolding & Parity Canary Gate
**Milestone:** M0 (primary execution), with FR-26's recurring display and FR-25's recurring re-grep continuing operationally through M2+.
**Goal:** Stand up the buildable Xcode project and repo from nothing, and execute (then keep re-executing) the parity-canary re-grep gate that must clear before any shim code exists.
**Maps to:** FR-25 (re-grep gate), FR-26 (version pin & changelog display) / NFR-6 (re-validation turnaround ≤1 business day).
**Dependencies:** None — this is the entry point of the whole pipeline. Blocks every other epic (E2–E12) via FR-25's hard-gate acceptance criterion.
**Exit criteria (execution-grounded):**
- `git init` done, Xcode project created, builds and launches a blank `NSWindow` on a clean checkout.
- A dated re-grep artifact (5-minute grep inventory, Spike B methodology) exists, timestamped after this session and diffed against Spike B's recorded table; any new namespace/method has a triage disposition recorded. No shim code is written until this artifact exists.
- A debug/About panel skeleton exists that can later display the validated Pass extension version + `WebClients` commit (FR-26 — full population happens once a version is actually validated in later epics; the *mechanism* ships here).
**Risks/notes:** This is process overhead for a solo dev, but CLAUDE.md and FR-25 both make it non-negotiable — resist the urge to skip straight to shim code. Re-grep needs to be re-run (NFR-6) on every subsequent Pass release; the automation for that recurring cadence is scoped fully in this epic's M2-era follow-up (it doesn't need a second epic, just later tasks against the same tooling).
**Size:** 0.5–1 weekend.

### E2 — Tier-1 API Stub Layer & Message Broker
**Milestone:** M1 — Risk 1 bucket.
**Goal:** Implement the ~45-method/~10-namespace Tier-1 stub surface (`alarms`, `storage`, `tabs`, `action`, `windows`, `permissions`, `scripting`, misc `runtime`) and the message broker (`runtime.sendMessage`/`onMessage`/`connect`/`onConnect`), which Spike B calls "the single most important piece" — everything else routes through it.
**Maps to:** FR-11 (Tier 1 stub layer), FR-10 (message broker).
**Dependencies:** E1 (canary gate must clear first — FR-25 hard prerequisite).
**Exit criteria:**
- With the shim active and the production Pass bundle loaded, zero unhandled `TypeError: browser.X.Y is not a function` in the background host's console during a login+unlock+autofill run (FR-11 acceptance — validated fully once E4/E6/E7 exist, but the stub surface itself is buildable and unit-testable here in isolation against stubbed inputs).
- A round-trip message from a content script reaches the background host and a reply is observed in the page; a persistent port survives ≥5 exchanges (FR-10 acceptance).
**Risks/notes:** Feeds directly into E6 (auth-fork bridge relies on `onMessageExternal` routing through this broker) and E7. Get the broker's message-shape contract right early — every later epic depends on it.
**Size:** ~1 weekend.

### E3 — Background Service-Worker Host
**Milestone:** M1 — Risk 1 bucket.
**Goal:** Stand up the hidden, always-resident WKWebView/JSContext that runs `background.js` with no MV3 suspend/wake cycle, and perform the global-scope API audit that FR-7 mandates.
**Maps to:** FR-7 (background host + its global-scope audit clause) / NFR-10 (background host ≤150 MB RSS steady-state, no unnecessary App Nap exemption), NFR-3 (contributes to overall footprint, measured fully once the shell exists).
**Dependencies:** E1.
**Exit criteria:**
- DevTools/target inspection shows the background target alive at launch, still alive after 30 minutes idle, and still alive after a full login flow.
- The global-scope audit log exists and lists **zero untriaged findings** before the skeleton (M1) is marked complete — this is also the deliverable E8 (risk 3 gate) checks against.
- RSS measurement of the hidden host is ≤150 MB steady-state (NFR-10) — measured here, gates fully at M2.
**Risks/notes:** This is Spike B risk 3's home. The audit clause inside FR-7's acceptance criterion is *produced* here but its zero-untriaged-findings bar is *re-checked* as the formal risk-3 gate in E8 — don't let "audit exists" substitute for "audit is clean" at the E8 checkpoint.
**Size:** ~0.5–1 weekend.

### E4 — Custom-Scheme Resource Handler
**Milestone:** M1 — Risk 2 bucket (sequenced *after* the risk-1 gate per PRD §9's mandated order — do not build/validate in parallel with E6).
**Goal:** Implement the `WKURLSchemeHandler` serving bundled extension resources (`dropdown.html`, `notification.html`, `*.wasm`) with correct web-accessible-resource semantics.
**Maps to:** FR-8 (custom-scheme resource handler).
**Dependencies:** E1; sequencing-gated behind E6 (risk 1 must pass first per the mandated risk-burn order — this is a process dependency, not a technical blocker).
**Exit criteria:**
- `dropdown.html` loads correctly as an iframe embedded from an arbitrary third-party `https` page.
- A request to a non-web-accessible path returns blocked/404.
- `*.wasm` resources serve with correct MIME type and execute (Pass's crypto payload).
**Risks/notes:** Feeds E7 directly (dropdown/popup rendering depends on this). CSP interaction on strict sites is the harder half of this epic — budget slack here rather than in E5.
**Size:** ~0.5–1 weekend.

### E5 — Content-World Injection & Frame Registry
**Milestone:** M1 — Risk 2 bucket (same sequencing constraint as E4).
**Goal:** Inject `orchestrator.js` (isolated `WKContentWorld`, `document_end`, all frames) and `webauthn.js` (MAIN world, `document_start`), and maintain a frame registry from `WKNavigationDelegate`/`WKFrameInfo` sufficient to answer `webNavigation.getFrame`/`getAllFrames`.
**Maps to:** FR-9 (content-world injection & frame registry).
**Dependencies:** E1; sequencing-gated behind E6.
**Exit criteria:**
- On a multi-iframe test page, `getAllFrames` returns the correct frame set including nested iframes.
- `webauthn.js`'s MAIN-world injection is observable via a scripted check.
**Risks/notes:** This is also where FR-24's Apple Pay injection-suspension tolerance eventually attaches (delivered in E10, M2) — note the coupling for the architecture phase: whatever injection-lifecycle abstraction this epic builds should anticipate a "suspended/resumed" state, even though the graceful-degradation behavior itself ships later.
**Size:** ~1 weekend.

### E6 — Minimal Shell & Auth-Fork Login (Risk 1 Gate)
**Milestone:** M1 — Risk 1 gate. **This is the first go/no-go checkpoint in the whole roadmap.**
**Goal:** Build just enough shell (one window, WKWebView rendering, URL navigation) to reach `account.proton.me`, then wire the auth-fork bridge (`runtime.onMessageExternal` relay from a content script injected only on `*.proton.me`) so a manual login is picked up under the **canonical** extension identity.
**Maps to:** FR-1 (single native window), FR-4 (WKWebView-only rendering), FR-5 (URL navigation), FR-13 (auth-fork login pickup).
**Dependencies:** E2 (message broker — the bridge relays through it), E3 (background host must be alive to receive the pickup event).
**Exit criteria (Spike B Risk 1 gate, PRD §9 row 1):**
- **[HUMAN GATE]** Calvin confirms readiness before the GUI window launches (ground rule 2); Calvin performs the manual login himself (ground rule 1) — Muninn never requests/reads/stores credentials.
- Background host observes a session-pickup event within 5 seconds of manual login.
- The shim's presented extension identity (`runtime.id` and the ID the bridge answers to) is the production canonical ID `ghmbeldphafepmbegfdlkpapadhbakde` — not a path-derived one (Spike A finding).
- **If this fails, per PRD §9: stop. Nothing downstream (E4/E5/E7/E8) is testable until this gate passes.** Escalate to D4's fallback ladder: (1) fix within shim scope, (2) pinned-tab Pass web app, (3) CEF window (last resort).
**Risks/notes:** Highest-risk epic in the roadmap by design — it's sequenced first specifically so a failure here is discovered before E4–E8's effort is sunk. No FR-2/3 tab model needed yet (single tab is sufficient per skeleton scope).
**Size:** ~1–1.5 weekends.

### E7 — Popup, Vault Unlock & Autofill Dropdown (Risk 2 Gate)
**Milestone:** M1 — Risk 2 gate.
**Goal:** Render `popup.html` in an `NSPopover`-hosted WKWebView for vault unlock, and render the field icon + dropdown iframe (`dropdown.html`) on a page with a detected login field, completing a credential fill on selection.
**Maps to:** FR-14 (toolbar popup & vault unlock), FR-15 (autofill dropdown) / NFR-1 (popup latency, measured here), NFR-7 (unlock-to-autofill latency, measured here).
**Dependencies:** E6 must pass first (mandated risk order); E4 (scheme handler serves `dropdown.html`/`popup.html`); E5 (frame registry + injection position the dropdown correctly).
**Exit criteria (Spike B Risk 2 gate, PRD §9 row 2):**
- Popup opens and renders Pass's own unlock UI within NFR-1's bound (measured, not yet gating).
- **[HUMAN GATE]** Calvin unlocks the vault himself entirely inside Pass's rendered UI — Muninn never observes/logs/intermediates the unlock secret. Popup visually reflects unlocked state afterward.
- On one real, strict-CSP-bearing site chosen for the skeleton: dropdown renders positioned correctly over the field; a selected credential fills the form. Verified against the **production** extension bundle, not a modified/side-loaded one.
- Success judged by Calvin's visual confirmation only — no plaintext values captured in logs/screenshots (ground rule 1).
**Risks/notes:** Strict-CSP interaction is the named risk here (Spike B risk 2) — pick the skeleton's target site deliberately for CSP strictness, not convenience, so the gate is meaningful.
**Size:** ~1–1.5 weekends.

### E8 — Service-Worker Audit, Egress Audit & Skeleton Privacy Exit (Risk 3 Gate + M1 Exit)
**Milestone:** M1 — Risk 3 gate and overall skeleton exit.
**Goal:** Confirm zero untriaged `ServiceWorkerGlobalScope` usage (closing out E3's audit), and run the full-session egress + plaintext-credential audit that gates the entire skeleton.
**Maps to:** FR-19 (no telemetry), FR-21 (no plaintext credential handling), FR-22 (egress allowlist for shell/shim-originated traffic) / NFR-5 (egress audit, P0 gate), NFR-8 (zero plaintext credentials, P0 gate, two-part: structural review + Calvin's own log search).
**Dependencies:** E7 must pass first (mandated risk order — this is validated only once login+unlock+autofill are all working end to end); consumes E3's audit log directly.
**Exit criteria (Spike B Risk 3 gate, PRD §9 row 3, plus overall skeleton exit = SM-1/SM-3):**
- E3's global-scope audit log shows zero untriaged findings.
- A full browse+login+autofill session captured via a filtering proxy classifies every outbound connection as page-initiated or shell/shim-originated; **100%** of shell/shim-originated connections match the FR-22 allowlist, **zero** unexplained shell/shim hosts (NFR-5).
- Network capture of a full session (launch → browse → login → autofill → quit) shows zero telemetry/analytics requests (FR-19).
- Structural review shows zero credential-shaped plaintext in Muninn-authored logs/crash payloads across a full UJ-1 run; **Calvin personally** searches logs for substrings of his own credentials — zero findings (NFR-8, both parts required).
- SM-1 declared met: all three risk flows pass end-to-end on the real production extension bundle under the canonical ID.
**Risks/notes:** This is the milestone's true exit gate, not just a risk checkpoint — Calvin's M1 sign-off (ground rule 3, phase-transition human gate) happens after this epic, not after E7.
**Size:** ~0.5–1 weekend.

### E9 — Daily-Driver Shell: Tabs, Session Restore, Navigation, Downloads, Default Browser
**Milestone:** M2.
**Goal:** Turn the single-tab skeleton into something dailydrivable — a minimal multi-tab model with session restore, back/forward/reload, file downloads, and default-browser registration.
**Maps to:** FR-2 (minimal multi-tab model, ≥8 tabs), FR-3 (session restore), FR-6 (background-tab behavior doesn't break the shim's frame registry/broker), FR-27 (navigation controls), FR-28 (downloads via `WKDownloadDelegate`), FR-29 (default-browser registration) / NFR-2 (cold-start ≤1.5s, now gating), NFR-4 (crash-free, ≤1 crash during SM-2 week).
**Dependencies:** E8 (M1 exit — building daily-driver shell on top of an unaudited skeleton would waste effort if the privacy exit gate had failed).
**Exit criteria:**
- 8 tabs opened, switched, 3 closed, remaining 5 persist, no crash (FR-2).
- Quit with 3 tabs at distinct URLs, relaunch, all 3 reopen in order with no further action (FR-3).
- With 3 tabs open, autofill succeeds on a background tab brought to focus without a full reload (FR-6).
- Two-navigations-deep page: back/forward/reload all work correctly (FR-27).
- A PDF and a .zip download to `~/Downloads` with visible progress; a cancelled download leaves no orphaned partial file (FR-28).
- Muninn appears in System Settings → Default web browser; after selection, a link clicked in Mail/Terminal opens in Muninn (FR-29).
- Window+tab visible within 1.5s cold start, max of 10 launches (NFR-2, now gating).
**Risks/notes:** This is the largest single epic by FR count (6 FRs) — a strong split candidate at story-planning time (e.g., "tab model," "session restore," "nav controls," "downloads," "default-browser registration" as separate stories under this epic).
**Size:** ~2–3 weekends.

### E10 — Pass v0.x Completions: Save-Login, Clipboard, Apple Pay Tolerance
**Milestone:** M2.
**Goal:** Complete the Pass user-visible flow set beyond the skeleton's login/unlock/autofill: save-login prompt, clipboard copy, and graceful degradation when WebKit suspends script injection during Apple Pay JS checkout.
**Maps to:** FR-16 (save-login prompt, Proton's stock heuristic), FR-17 (clipboard write via `NSPasteboard`), FR-24 (Apple Pay injection-suspension tolerance) / NFR-1 (popup latency, now gating), NFR-7 (unlock-to-autofill latency, now gating).
**Dependencies:** E8; benefits from E9's tab model existing but not strictly blocked by it.
**Exit criteria:**
- After submitting a login form with a new credential on a test site, the save-login notification appears using Proton's stock heuristic — no custom form-failure inference added (FR-16).
- Using a **dedicated dummy vault item** (never a real secret), "copy password" places the expected value on the pasteboard; verified by Calvin's own paste-and-look, agent never reads the pasteboard (FR-17, ground rule 1).
- Shim does not crash and frame registry stays intact when injection is unavailable on a page; injection resumes on next navigation — verified via fault injection (real Apple Pay merchant-session verification is deferred to E12/M3 per FR-24's own acceptance caveat) (FR-24).
- Popup latency ≤300ms (max of 20 trials) and unlock-to-autofill ≤1s (max of 10 trials) now hold as binding gates, not just measurements (NFR-1, NFR-7).
**Risks/notes:** FR-24's *full* verification needs a live Apple Pay merchant session per its own acceptance caveat — this epic delivers the fault-injected graceful-degradation path only; flag the live-session test as an M3 follow-up (see E12).
**Size:** ~1–2 weekends.

### E11 — Privacy v0.x: Content Blocking & Telemetry/Resource Re-verification
**Milestone:** M2.
**Goal:** Compile and apply a `WKContentRuleList` from EasyList/EasyPrivacy with a manual update command, and re-verify the P0 privacy/footprint bars now hold under full daily-driver load.
**Maps to:** FR-20 (content blocking) / NFR-9 (≥95% tracker-request blocking, zero compile errors), plus re-verification of NFR-3 (≤400MB RSS steady-state) and NFR-10 (background host ≤150MB) under the full v0.x shell rather than the skeleton's single tab.
**Dependencies:** E8; independent of E9/E10 (can interleave).
**Exit criteria:**
- Compiled `WKContentRuleList` loads with zero compile errors.
- On a reference tracker test page, ≥95% of tracker requests are blocked and the page still functions (NFR-9).
- With the full v0.x shell (multi-tab, session restore, background host) idle 10 minutes, RSS ≤400MB total / ≤150MB for the background host specifically (NFR-3, NFR-10 — re-measured, not first-measured).
**Risks/notes:** OQ-4's resolution (EasyList+EasyPrivacy, manual update, no automatic background fetch) is locked by the PRD — don't scope-creep into scheduled auto-updates, which the PRD explicitly defers as needing its own egress-allowlist/scheduling design.
**Size:** ~1 weekend.

### E12 — Hardening & Distribution (P2, opportunistic)
**Milestone:** M3.
**Goal:** Ship the optional/deferred items the PRD marks P2 and unscheduled: passkey ceremonies, the app-level biometric content gate, the OQ-6 biometric-vault-unlock investigation, distribution polish (signing/notarization), and the FR-24 live-merchant Apple Pay follow-up.
**Maps to:** FR-12 (`nativeMessaging` no-op stub), FR-18 (passkeys via `ASAuthorization`), FR-23 (app-level biometric gate, `LocalAuthentication .biometryOrWatch`) — plus non-FR follow-ups: OQ-6 investigation (feasibility of Pass's own extension-side biometric unlock, or scoping FR-12 into something real later), OQ-5 resolution execution (signed + notarized direct-download build), and FR-24's live Apple Pay merchant-session verification (deferred from E10).
**Dependencies:** E9, E10, E11 (M2 exit / SM-2 recommended before starting, though individual items like FR-23 have no hard technical dependency on the tab model and could be pulled forward if desired — flagged as a sequencing option, not a rule).
**Exit criteria:**
- Extension functions normally with the `nativeMessaging` stub present; no crash/unhandled rejection on `connectNative` calls (FR-12).
- A WebAuthn `navigator.credentials.get/create` call on a passkey-enabled test site completes via `ASAuthorization` without crash/hang (FR-18).
- Locking the Mac and returning triggers the biometric prompt before content redisplays; declining keeps content hidden; the flow never touches Pass's own unlock state (FR-23).
- OQ-6 investigation produces a recorded finding (feasible/not, and how) rather than silently staying open.
- Signed + notarized build installs and runs without Gatekeeper warnings (OQ-5 execution).
- FR-24's graceful-degradation path is verified against a live Apple Pay merchant checkout session, closing the caveat left open in E10.
**Risks/notes:** This epic is explicitly unscheduled per PRD §9 — no single exit gate blocks anything downstream; each item ships and gets Calvin's sign-off independently. AS-7 flags that Apple Developer Program enrollment for signing/notarization is not yet confirmed active — verify before committing weekend time here.
**Size:** ~2–4 weekends, as-desired.

---

## 3. Traceability Appendix

### FR → Epic (every FR appears exactly once)

| FR | Epic | FR | Epic | FR | Epic |
|---|---|---|---|---|---|
| FR-1 | E6 | FR-11 | E2 | FR-21 | E8 |
| FR-2 | E9 | FR-12 | E12 | FR-22 | E8 |
| FR-3 | E9 | FR-13 | E6 | FR-23 | E12 |
| FR-4 | E6 | FR-14 | E7 | FR-24 | E10 |
| FR-5 | E6 | FR-15 | E7 | FR-25 | E1 |
| FR-6 | E9 | FR-16 | E10 | FR-26 | E1 |
| FR-7 | E3 | FR-17 | E10 | FR-27 | E9 |
| FR-8 | E4 | FR-18 | E12 | FR-28 | E9 |
| FR-9 | E5 | FR-19 | E8 | FR-29 | E9 |
| FR-10 | E2 | FR-20 | E11 | | |

### NFR → Gate location

| NFR | Gates at | Notes |
|---|---|---|
| NFR-1 | Measured E7 (M1) → binding gate E10 (M2) | Popup latency ≤300ms |
| NFR-2 | Measured E6 (M1, single tab) → binding gate E9 (M2, full session restore) | Cold start ≤1.5s |
| NFR-3 | Measured E3 (M1) → binding re-verification E11 (M2, full shell) | ≤400MB RSS steady-state |
| NFR-4 | Gate E9 / overall M2 exit (SM-2) | ≤1 crash during the one-week test; skeleton exempt |
| NFR-5 | Gate E8 (P0, M1 exit) | Egress audit — shell/shim traffic only |
| NFR-6 | Gate E1 (ongoing) | Re-grep turnaround ≤1 business day of a Pass release |
| NFR-7 | Measured E7 (M1) → binding gate E10 (M2) | Unlock-to-autofill ≤1s |
| NFR-8 | Gate E8 (P0, M1 exit); re-checked at every milestone gate per its own acceptance text | Zero plaintext credentials — structural + Calvin's own search |
| NFR-9 | Gate E11 (M2) | ≥95% tracker-request blocking |
| NFR-10 | Gate E3 (M1) → binding re-verification E11 (M2) | Background host ≤150MB RSS |

### SM / OQ → where resolved

| ID | Where |
|---|---|
| SM-1 | E8 exit (M1) — three risk flows pass on production bundle, canonical ID |
| SM-2 | E9/E10/E11 collective exit (M2) — one-week default-browser test |
| SM-3 | E8 (initial), re-verified through M2 — egress audit shows only allowlisted hosts |
| SM-4 | E10 (M2) — latency targets binding |
| OQ-1 (shell scope) | Resolved by E9's scope (minimal tab model + session restore only) |
| OQ-2 (save-login parity) | Resolved by E10 (accept stock heuristic) |
| OQ-3 (sync) | Explicitly out of scope of this roadmap — future PRD |
| OQ-4 (content blocking) | Resolved by E11 (EasyList+EasyPrivacy, manual update) |
| OQ-5 (distribution) | Executed in E12 (signed+notarized direct download) |
| OQ-6 (biometric vault unlock) | Investigated (not resolved) in E12 |

---

## 4. Sequencing & Dependency Graph

Mandated risk-burn order (PRD §9) is a hard sequencing constraint within M1 — risk buckets are gated, not parallelized. M2 epics may interleave freely once M1 exits. M3 is opportunistic.

```
E1 (Foundations / FR-25 gate)
   │
   ├──────────────┬───────────────┐
   ▼              ▼               │
  E2            E3                │   (Risk 1 subsystems — parallel-buildable)
  (stubs/       (background       │
   broker)       host)            │
   │              │               │
   └──────┬───────┘               │
          ▼                       │
         E6  ◄── [RISK 1 GATE] ───┘   auth-fork login, canonical ID
          │        (STOP if this fails — D4 fallback ladder)
          │
   ┌──────┴───────┐
   ▼               ▼
  E4              E5                (Risk 2 subsystems — gated behind E6,
  (scheme          (injection/       parallel-buildable with each other)
   handler)         frame registry)
   │               │
   └──────┬────────┘
          ▼
         E7  ◄── [RISK 2 GATE]        popup/unlock/dropdown/autofill
          │
          ▼
         E8  ◄── [RISK 3 GATE + M1 EXIT / SM-1 / SM-3]
          │        SW audit clean + egress/privacy audit clean
          │
   ┌──────┼───────────────┐
   ▼      ▼               ▼
  E9     E10             E11         (M2 — free to interleave)
 (shell) (Pass v0.x)     (privacy v0.x)
   │      │               │
   └──────┴───────┬───────┘
                   ▼
                  [M2 EXIT / SM-2 — one calendar week]
                   │
                   ▼
                  E12  (M3 — opportunistic, unscheduled)

   Horizon: Sync — no edge into this graph; own future PRD (OQ-3).
```

---

## 5. Gaps Noticed (not scope additions — flagging for architecture/story phases)

- **No FR owns the egress-audit tooling itself.** NFR-5 describes the measurement procedure (filtering proxy per Spike A's follow-up mini-spike) and E8 executes it, but no FR in the PRD assigns ownership of *building* that proxy/tooling. Recommend the architecture phase decide whether it's a throwaway manual setup (mitmproxy config, one-off) or a reusable harness folded into E1; either is legitimate, but it should be a conscious decision, not a silent gap at story time.
- **No FR owns acquiring/vendoring the production Pass extension bundle.** AS-8 notes this is "an architecture-phase decision" (store download vs. `WebClients` build vs. vendored copy) but no FR formally assigns it to an epic. It's a hard prerequisite for E6/E7/E8's acceptance criteria (all require "the production extension bundle"). Recommend the architecture phase pin the mechanism and the story-planner add it as an explicit early task under E1 or E6.
- **FR-24's acceptance criterion contains its own scoping caveat** (live Apple Pay merchant session may be needed for full verification; a test harness for this is called out as "an architecture-phase question"). This roadmap splits FR-24 into an E10 fault-injection delivery and an E12 live-session follow-up rather than blocking M2 on an external dependency (a live merchant checkout) — flagging this split explicitly since it's an interpretation, not a literal PRD instruction.
- **Distribution work (signing/notarization) has no dedicated FR** — it exists only as OQ-5's proposed resolution and a §8 non-goal note ("revisit Mac App Store at 1.0"). E12 executes OQ-5's resolution as roadmap scope, but there is no FR-N to cite for it; the traceability table above marks it via OQ-5, not an FR, and AS-7 flags the underlying Apple Developer Program enrollment as unconfirmed.

---

## 6. Approval

**HUMAN GATE — Calvin Ference**

> *(verbatim verdict and timestamp to be recorded here upon review — intended to be approved alongside or immediately after `prd.md` §13, since this roadmap is derived from and inherits that gate)*

Status: **Awaiting approval.**
