# Muninn — Product Requirements Document (PRD)

**Version:** 0.1 DRAFT
**Date:** 2026-07-11
**Status:** Awaiting approval — **HUMAN GATE (Calvin)**
**Provenance:** Derived from `product-brief.md`, `decisions.md`, `CLAUDE.md` (ground rules & technical facts), `research/spike-a-results.md`, and `research/spike-b-proton-pass-api-inventory.md` (all dated 2026-07-11). Locked decisions D1–D4 in `decisions.md` are treated as constraints, not re-litigated here.
**Review record:** Draft reviewed by a separate checker agent 2026-07-11; 6 blocking findings fixed in this revision (JTBD-3 deferral made explicit, daily-driver FR-27…29 added, egress audit scoped to shell/shim-originated traffic, FR-10/FR-17 acceptance made executable, D4 fallback contingency referenced).

---

## 1. Vision & Goals

A privacy-first, Apple-native macOS browser with a calm, fully custom (Arc-like) shell, built around Proton Pass as its password manager. Muninn knows everything about your browsing and tells no one — Odin's raven, reporting only to you.

Goal of this PRD: lock the **what** for the first shippable slice — a walking skeleton that proves the browser can host Proton Pass's real login, unlock, and autofill flows on WKWebView (D2) — and sketch, at lower resolution, the daily-driver trajectory that follows it.

---

## 2. Target User & Jobs to Be Done

**Primary user (and sole user through v0.x): Calvin Ference** — Scala developer, privacy-conscious Proton user (`@proton.me`), deep in the Apple ecosystem (MacBook, iPhone, iPad, Apple Watch). Design for personal daily-driver quality first; general audience is out of scope for this PRD.

| ID | Job to be done |
|---|---|
| JTBD-1 | Browse with a shell that stays out of the way (custom, minimal, Arc-like — drove the engine decision, D2). |
| JTBD-2 | Log in everywhere with Proton Pass: field icon, dropdown, autofill, save-login — at parity with Pass-in-Safari. |
| JTBD-3 | Unlock the vault the Apple way: Touch ID / Apple Watch double-tap. **Deferred in this PRD** — see OQ-6 (§12): true biometric *vault* unlock needs either Pass's extension-side biometric support or the deferred `nativeMessaging` desktop integration (FR-12); the skeleton and v0.x use Pass's own in-popup unlock (FR-14). FR-23 is a related but distinct app-level gate, not this job. |
| JTBD-4 | Keep browsing private: no engine phone-home, content blocking, no third-party telemetry. |
| JTBD-5 | (Later) Sync tabs/history across devices via an owner-controlled Scala service. |

---

## 3. Glossary

| Term | Meaning |
|---|---|
| **Shim** | The purpose-built Swift runtime that implements Proton Pass's Safari-profile `chrome.*`/`browser.*` API surface (~10 namespaces, ~45 methods) over native WKWebView/AppKit primitives, per Spike B. Not a general extension platform. |
| **Walking skeleton** | The MVP: one window, one tab, shim runtime up, proving login → vault unlock → autofill end-to-end on one real site. |
| **Auth fork** | Proton's login flow in which `account.proton.me` hands a session to the extension via `runtime.onMessageExternal` / `externally_connectable`, rather than the extension driving login itself. Risk 1. |
| **Content world** | A `WKContentWorld` — an isolated JavaScript execution context. Used to replicate Pass's isolated-world vs. MAIN-world content-script injection (`orchestrator.js` vs. `webauthn.js`). |
| **Web-accessible resources** | Extension-bundled files (`dropdown.html`, `notification.html`, `*.wasm`) that arbitrary web pages may embed/fetch by convention; the scheme handler must replicate this access policy. |
| **Parity canary** | Proton's own Safari (WebKit) build. Because it already excludes every API the shim would find hard (`webRequest`, `offscreen`, `privacy`, `commands`), it defines the shim's permanent target profile — re-checked on every Pass release. |
| **Canonical extension ID** | The production extension ID (`ghmbeldphafepmbegfdlkpapadhbakde`) derived from the CRX3 public key, as opposed to a path-derived ID from unpacked side-loading. `onMessageExternal` pickup is keyed to the canonical ID (Spike A finding). |
| **Background host** | The always-alive hidden WKWebView/JSContext that runs `background.js` (Pass's MV3 service worker) with no suspend/wake lifecycle. |
| **Frame registry** | A native map from `WKFrameInfo`/`WKNavigationDelegate` events, backing `webNavigation.getFrame`/`getAllFrames`. |
| **Message broker** | The `WKScriptMessageHandler` (page → shim) + `evaluateJavaScript` (shim → page) router implementing `runtime.sendMessage`/`onMessage`/`connect`/`onConnect`. |
| **Egress allowlist** | The finite set of hosts the **shell/shim layer** (Muninn-authored native code and the background host) is permitted to contact outbound: Proton API/account domains required by the shim and Apple system services required by WebKit/LocalAuthentication/ASAuthorization. **Page-initiated traffic** (the loaded document and its subresources — CDNs, third-party scripts) is a separate class, attributable to the user's navigation and out of the allowlist's scope; trackers within it are the content blocker's job (FR-20), not the audit's. |

---

## 4. User Journeys (MVP + near-term)

### UJ-1 — Login → Unlock → Autofill (the walking skeleton, i.e. the acceptance journey for FR-13/14/15)

1. **[HUMAN GATE]** Calvin confirms in chat he's ready before Muninn (a GUI window) is launched (ground rule 2).
2. Muninn opens one window with one WKWebView tab; the shim's background host starts and stays resident.
3. Calvin (or the tab, pre-navigated) loads `account.proton.me`.
4. **[HUMAN GATE]** Calvin performs login directly in the page — Muninn/the agent never requests, reads, or stores credentials (ground rule 1).
5. The auth-fork bridge script relays session pickup from the page to the shim (FR-13); the background host receives it.
6. Calvin clicks the toolbar action icon; an `NSPopover`-hosted `popup.html` opens (FR-14).
7. **[HUMAN GATE]** Calvin unlocks the vault himself, entirely inside Pass's own popup UI — Muninn does not observe, log, or intermediate the unlock secret.
8. Calvin navigates the tab to one real site with a login form.
9. The field icon and dropdown iframe appear over the form (FR-15); Calvin selects a credential; the form is filled.
10. Success is judged by visual confirmation (Calvin) that the correct fields were populated — plaintext values are never captured in logs/screenshots per ground rule 1.

### UJ-2 — Daily browsing (v0.x, post-skeleton)

1. Calvin launches Muninn; the previous session's tabs restore (FR-3).
2. Calvin opens/closes/switches tabs via the tab strip/switcher (FR-2).
3. Trackers on visited pages are silently blocked (FR-20) without breaking page function.
4. No unexpected outbound hosts appear in a periodic egress audit (FR-22, NFR-5).

### UJ-3 — Lock / unlock

1. Calvin backgrounds Muninn or the Mac locks.
2. On return, Muninn **may** ask for Touch ID/Watch as an app-level privacy gate before redisplaying page content (FR-23) — this is a Muninn-native convenience layer, separate from Pass.
3. Separately, if Pass's own vault has re-locked per its own timeout policy, Calvin unlocks it exactly as in UJ-1 step 7 — inside Pass's own UI, never through Muninn.
4. Browsing resumes.

---

## 5. Requirement Conventions

Statements use RFC-2119 keywords (SHALL / SHALL NOT / SHOULD / MAY). Priority: **P0** = required for the walking skeleton (MVP); **P1** = required for daily-driver v0.x; **P2** = later / opportunistic. Every requirement cites its source artifact and states a testable acceptance criterion.

---

## 6. Functional Requirements

### 6.1 Shell & Window

**FR-1 — Single native window on launch.** *(P0)*
Statement: The shell SHALL launch as a native AppKit macOS application and present exactly one application window on a clean launch (no saved session).
Source: `product-brief.md` (MVP "one window"); `decisions.md` D3 (Swift/AppKit shell).
Acceptance: On a launch with no prior session state, exactly one `NSWindow` exists (verified via debug window count or Accessibility Inspector).

**FR-2 — Minimal multi-tab model.** *(P1)*
Statement: The shell SHOULD provide a tab strip or switcher allowing Calvin to open, close, and switch between at least 8 concurrent tabs.
Source: Open Question 1 (§12), proposed resolution.
Acceptance: Manual test opens 8 tabs, switches among them, closes 3; the remaining 5 persist correctly and no crash occurs.

**FR-3 — Session restore.** *(P1)*
Statement: On relaunch, the shell SHALL restore the tab URLs open at last quit (or crash) within the cold-start bound (NFR-2).
Source: Open Question 1 (§12).
Acceptance: Quit with 3 tabs open at distinct URLs; relaunch; all 3 reopen as tabs (order preserved) with no further action.

### 6.2 Engine & Tab

**FR-4 — WKWebView-only rendering.** *(P0)*
Statement: Muninn SHALL render all web content exclusively via system WebKit (`WKWebView`); no other browser engine SHALL be embedded.
Source: `decisions.md` D2.
Acceptance: No CEF/JCEF/Chromium binary or framework is linked into the shipped app; a build-artifact inspection confirms only WebKit.framework is used for rendering.

**FR-5 — URL navigation / address entry.** *(P0)*
Statement: Each tab SHALL accept a URL or search-style query and navigate the underlying `WKWebView` to it.
Source: `product-brief.md` MVP (implicit — reaching `account.proton.me` and a target site requires navigation).
Acceptance: Entering `https://account.proton.me` and a second real-site URL both result in successful page loads in the same tab session.

**FR-6 — Reasonable background-tab behavior.** *(P1)*
Statement: With multiple tabs open (FR-2), background (non-focused) tabs SHOULD NOT be silently suspended in a way that breaks the shim's frame registry or message broker for that tab.
Source: `research/spike-b-proton-pass-api-inventory.md` (frame registry, message broker).
Acceptance: With 3 tabs open, autofill (FR-15) succeeds on a background tab brought to focus without a full page reload.

### 6.3 Shim Runtime — Tier 2 Subsystems

**FR-7 — Background service-worker host.** *(P0)*
Statement: The shim SHALL run `background.js` inside a hidden, always-resident WKWebView (or JSContext) loaded via the custom scheme, kept alive for the lifetime of the app process with no MV3 suspend/wake cycle. Once the host loads successfully, a global-scope API audit (Spike B risk 3) SHALL be performed and any use of a `ServiceWorkerGlobalScope`-only API not already covered by Tier 1/2 stubs SHALL be logged and triaged.
Source: `research/spike-b-proton-pass-api-inventory.md` Tier 2; Spike B risk 3.
Acceptance: DevTools/target inspection shows the background target alive at app launch and still alive after 30 minutes idle and after a full login flow; the global-scope audit log exists and lists zero untriaged findings before the skeleton is marked complete.

**FR-8 — Custom-scheme resource handler.** *(P0)*
Statement: A `WKURLSchemeHandler` SHALL serve bundled extension resources (including `dropdown.html`, `notification.html`, `*.wasm`) over a custom scheme, replicating web-accessible-resource semantics: embeddable/fetchable from any `http(s)` page, blocked from all other origins.
Source: `research/spike-b-proton-pass-api-inventory.md` Tier 2; Spike B risk 2.
Acceptance: `dropdown.html` loads correctly as an iframe embedded from an arbitrary third-party `https` page; a request from a non-web-accessible path returns a blocked/404 response; `*.wasm` resources are served with correct MIME type and execute.

**FR-9 — Content-world injection & frame registry.** *(P0)*
Statement: The shim SHALL inject `orchestrator.js` into all frames at `document_end` in an isolated `WKContentWorld`, inject `webauthn.js` at `document_start` in the MAIN world, and SHALL maintain a frame registry (from `WKNavigationDelegate`/`WKFrameInfo`) sufficient to answer `webNavigation.getFrame`/`getAllFrames`.
Source: `research/spike-b-proton-pass-api-inventory.md` Tier 2.
Acceptance: On a multi-iframe test page, `getAllFrames` returns the correct frame set including nested iframes; `webauthn.js` global-scope injection is observable in the page's MAIN world via a scripted check.

**FR-10 — Message broker.** *(P0)*
Statement: The shim SHALL implement `runtime.sendMessage`, `onMessage`, `connect`, and `onConnect` (ports) via a `WKScriptMessageHandler` (page → shim) and `evaluateJavaScript` (shim → page) router.
Source: `research/spike-b-proton-pass-api-inventory.md` Tier 1 (message broker called out as "the single most important piece").
Acceptance: A round-trip message sent from a content script reaches the background host and a reply is observed back in the page (functional check — no latency gate at skeleton stage; end-to-end responsiveness is covered by NFR-7 at the autofill level); a persistent port stays connected across at least 5 message exchanges.

**FR-11 — Tier 1 API stub layer.** *(P0)*
Statement: The shim SHALL implement the Tier 1 namespaces (`alarms`, `storage`, `tabs`, `action`, `windows`, `permissions`, `scripting` — `executeScript`/`insertCSS` via `evaluateJavaScript(in:frame:contentWorld:)` — and misc `runtime`) as native shims sufficient for `background.js` and content scripts to run without throwing on unimplemented API calls.
Source: `research/spike-b-proton-pass-api-inventory.md` Tier 1 (~45 methods, ~10 namespaces, ~80% of call sites).
Acceptance: With the shim active and the production Pass extension bundle loaded, zero unhandled `TypeError: browser.X.Y is not a function` errors appear in the background host's console during a full login+unlock+autofill run.

**FR-12 — `nativeMessaging` stub (deferred).** *(P2)*
Statement: The shim MAY expose `connectNative`/`sendNativeMessage` as no-op stubs so the extension does not error if it probes for them; full desktop-app lock-state integration is out of scope.
Source: `research/spike-b-proton-pass-api-inventory.md` Tier 3 ("defer").
Acceptance: Extension functions normally with the stub present; no crash or unhandled rejection when the extension calls `connectNative`.

### 6.4 Pass User-Visible Flows

**FR-13 — Auth-fork login pickup.** *(P0 — Risk 1)*
Statement: A bridge content script SHALL be injected only on `*.proton.me` to relay `postMessage` traffic from the account web app to the shim via `runtime.onMessageExternal`, so that a manual login at `account.proton.me` is picked up by the extension without further user action.
Source: `research/spike-b-proton-pass-api-inventory.md` risk 1; `research/spike-a-results.md` (canonical extension ID requirement).
Acceptance: After manual login at `account.proton.me` (human-performed per ground rule 1), the background host observes a session-pickup event within 5 seconds. The shim's extension identity as presented to `*.proton.me` (`runtime.id` and the ID the bridge answers to) SHALL be the production canonical ID `ghmbeldphafepmbegfdlkpapadhbakde` — the account web app targets that ID, so a path-derived or made-up identity silently breaks pickup (Spike A finding, generalized from the CRX case).

**FR-14 — Toolbar popup & vault unlock.** *(P0)*
Statement: An `NSPopover`-hosted `WKWebView` SHALL render `popup.html`; vault unlock SHALL occur entirely inside this rendered Pass UI, driven only by the human.
Source: `research/spike-a-results.md` Test 1 checks 1.4; `decisions.md` D2 (Apple ecosystem posture); ground rule 1.
Acceptance: Popup opens within NFR-1's latency bound and renders Pass's own unlock UI; after Calvin unlocks manually, the popup reflects unlocked state (verified visually, not logged).

**FR-15 — Autofill dropdown.** *(P0 — Risk 2)*
Statement: On a page with a detected login field, the shim SHALL render the field icon and, on interaction, the dropdown iframe (`dropdown.html`), and SHALL complete a credential fill into the page's form fields on user selection.
Source: `research/spike-b-proton-pass-api-inventory.md` risk 2; `research/spike-a-results.md` Test 1 check 1.5.
Acceptance: On one real, strict-CSP-bearing site (chosen for the skeleton), the dropdown renders positioned correctly over the field and a selected credential fills the form; verified against the production extension bundle, not a modified/side-loaded one.

**FR-16 — Save-login prompt.** *(P1)*
Statement: The shim SHOULD surface Pass's save-login notification (`notification.html`) using Proton's existing (degraded, `webRequest`-less) Safari-profile heuristic for detecting successful form submission.
Source: `research/spike-b-proton-pass-api-inventory.md` Tier 3 (`webRequest` skip); Open Question 2 (§12) proposed resolution.
Acceptance: After submitting a login form with a new credential on a test site, the save-login notification appears using the stock heuristic, with no custom form-failure inference added.

**FR-17 — Copy-to-clipboard.** *(P1)*
Statement: The shim SHALL implement `clipboardWrite` via `NSPasteboard` so that "copy password" actions in the popup/dropdown function.
Source: `research/spike-b-proton-pass-api-inventory.md` Tier 2 (`clipboardWrite`).
Acceptance: Using a dedicated **dummy vault item** (throwaway credential created for testing, never a real secret), triggering "copy" in the popup places the expected value on the system pasteboard; verification is by **Calvin's visual confirmation only** (paste into a scratch field he inspects himself) — the agent never reads the pasteboard or the field, per ground rule 1.

**FR-18 — Passkeys.** *(P2)*
Statement: Muninn MAY integrate `ASAuthorization` to support WebAuthn/passkey ceremonies that Pass's `webauthn.js` (MAIN-world injection, FR-9) may trigger.
Source: `decisions.md` D2 (Apple ecosystem note); CLAUDE.md Apple-native affordances.
Acceptance: A WebAuthn `navigator.credentials.get/create` call on a passkey-enabled test site completes via the native `ASAuthorization` sheet without the shim crashing or hanging.

### 6.5 Privacy

**FR-19 — No telemetry.** *(P0)*
Statement: Muninn SHALL NOT transmit usage analytics, crash reports, or any telemetry to a Muninn-operated or third-party analytics endpoint by default; if diagnostics are ever added, they SHALL be opt-in.
Source: `product-brief.md` JTBD-4; vision statement.
Acceptance: A network capture of a full session (launch, browse, login, autofill, quit) contains zero requests to any analytics/telemetry endpoint.

**FR-20 — Content blocking.** *(P1)*
Statement: Muninn SHOULD compile a `WKContentRuleList` from EasyList and EasyPrivacy and apply it to block tracker/ad requests, with a manual command to trigger list updates.
Source: Open Question 4 (§12) proposed resolution.
Acceptance: The compiled rule list loads without error; see NFR-9 for effectiveness bar.

**FR-21 — No plaintext credential handling in shim code.** *(P0)*
Statement: The shim SHALL NOT log, persist, or transmit vault contents, passwords, TOTP codes, or derived unlock secrets in plaintext at the native layer; it SHALL only relay Pass's own (already-encrypted-or-ephemeral) messages between page and background host.
Source: CLAUDE.md ground rule 1; `product-brief.md` constraints.
Acceptance: Static/manual review of all Muninn-authored log statements and crash-report payloads shows zero occurrences of credential-shaped plaintext across a full UJ-1 run (see NFR-8).

**FR-22 — Egress allowlist by default.** *(P0)*
Statement: **Shell/shim-originated** outbound connections (Muninn-authored native code plus the background host) SHALL be limited to (a) Proton API/account hosts required by the shim and (b) Apple system services required by WebKit/LocalAuthentication/ASAuthorization. **Page-initiated traffic** (the navigated document and its subresources) is attributable to the user's navigation and is outside the allowlist — the audit's job is to catch *shell/engine phone-home*, not page content (see glossary "Egress allowlist").
Source: `product-brief.md` success metrics (egress audit); `research/spike-a-results.md` privacy posture note (which targets engine-originated background traffic: GCM, component updater, etc.).
Acceptance: See NFR-5 for the measured audit procedure and traffic classification.

### 6.6 Apple Integration

**FR-23 — App-level biometric gate.** *(P2)*
Statement: Muninn MAY require Touch ID or Apple Watch confirmation (via `LocalAuthentication`, `.biometryOrWatch`-style policy) before redisplaying page content after the app returns from background/lock — as a Muninn-native convenience layer, entirely separate from and never a substitute for Pass's own vault unlock (FR-14). Note: this does **not** satisfy JTBD-3 (biometric *vault* unlock), which is deferred — see OQ-6.
Source: `decisions.md` D2 (Apple ecosystem); CLAUDE.md Apple-native affordances (`LocalAuthentication ...OrWatch`).
Acceptance: Locking the Mac and returning triggers the native biometric prompt before content is shown; declining the prompt keeps content hidden; the flow never touches Pass's own unlock state.

**FR-24 — Apple Pay JS injection-suspension tolerance.** *(P1)*
Statement: The shim SHALL detect when WebKit disables script injection on an active page (Apple Pay JS checkout flows) and SHALL degrade gracefully — no crash, and injection SHALL resume automatically once the page navigates away from the checkout context.
Source: CLAUDE.md "WKWebView niceties confirmed relevant."
Acceptance: The shim does not crash or leave the frame registry in a broken state when injection is unavailable on a page, and injection resumes on the next navigation. *Caveat (reviewer finding): triggering WebKit's real injection-suspension may require a live Apple Pay merchant session — constructing a test harness for this is an architecture-phase question; until then the graceful-degradation path is verified by fault injection (simulating injection failure).*

### 6.7 Maintenance

**FR-25 — Parity-canary re-validation gate.** *(P0)*
Statement: Before any shim implementation work begins, and before each subsequent Proton Pass extension version bump, the 5-minute grep inventory (Spike B methodology) SHALL be re-run against `ProtonMail/WebClients` main and diffed against the recorded Safari-manifest permission set; any newly appearing namespace/method SHALL be triaged into Tier 1/2/3 before implementation proceeds.
Source: CLAUDE.md ("re-run Spike B's grep inventory... before shim implementation starts"); `research/spike-b-proton-pass-api-inventory.md` (inventory taken 2026-07-11 vs. Pass v1.38.2, "re-run before committing").
Acceptance: A dated re-grep artifact exists, timestamped after the current session and before the first line of shim code is written; any diff from Spike B's table is recorded with a triage disposition.

**FR-26 — Version pin & changelog.** *(P1)*
Statement: Muninn SHOULD record the exact Proton Pass extension version (and `WebClients` commit) the shim was last validated against, surfaced in an internal "About Muninn" or debug panel.
Source: `research/spike-b-proton-pass-api-inventory.md` (maintenance tail).
Acceptance: The debug panel displays a version string matching the last FR-25 re-validation run.

### 6.8 Daily-Driver Essentials (added post-review — preconditions for SM-2)

**FR-27 — Navigation controls.** *(P1)*
Statement: Each tab SHALL provide back, forward, and reload controls wired to the `WKWebView` navigation stack.
Source: Reviewer finding vs. SM-2 (a week of default-browser use requires basic navigation); implicit in JTBD-1.
Acceptance: On a page two navigations deep, back returns to the prior page, forward re-advances, and reload re-fetches the current page.

**FR-28 — Downloads.** *(P1)*
Statement: Muninn SHALL handle file downloads via `WKDownloadDelegate`, saving to the user's Downloads folder with visible progress and completion indication; downloads SHALL NOT silently fail.
Source: Reviewer finding vs. SM-2; WKWebView requires an explicit download delegate.
Acceptance: Downloading a test file (e.g., a PDF and a .zip) completes to `~/Downloads` with progress shown; a cancelled download leaves no orphaned partial file.

**FR-29 — Default-browser registration.** *(P1)*
Statement: Muninn SHALL declare itself as a handler for `http`/`https` URL schemes (Info.plist `CFBundleURLTypes` + `LSHandlerRank`) such that macOS System Settings can select it as the default browser, and SHALL open externally-clicked links in a tab.
Source: Reviewer finding — hard precondition for SM-2's one-week default-browser test.
Acceptance: Muninn appears in System Settings → Desktop & Dock → Default web browser; after selection, a link clicked in Mail/Terminal opens in Muninn.

*History, bookmarks, and find-in-page are NOT required for SM-2 (P2, unscheduled) — the one-week test tolerates their absence; add them only if the week reveals real friction.*

---

## 7. Non-Functional Requirements

| ID | Requirement | Target / Verification | Priority | Relates to |
|---|---|---|---|---|
| NFR-1 | Popup open latency | `popup.html` visually complete and interactive within **300 ms (max of 20 trials)** of toolbar-icon click, via timestamp logging (contrast: CEF's "very slow to open" per Spike A gate 1.4). **Measured-and-recorded at the skeleton; becomes a gate at v0.x** — a working-but-slow skeleton is not blocked on perf tuning. | P1 (measured at P0 stage) | FR-14 |
| NFR-2 | Cold-start time | Window + tab visible within **1.5 s (max of 10 launches)** from process launch on Apple Silicon, via `os_signpost` or stopwatch. Measured at skeleton; gates at v0.x. | P1 (measured at P0 stage) | FR-1 |
| NFR-3 | Steady-state memory footprint | Shell + one `WKWebView` tab + background host ≤ **400 MB RSS** after 10 min idle, measured via Activity Monitor/`vmmap`. | P1 | FR-4, FR-7 |
| NFR-4 | Crash-free sessions | **At most 1 crash** during the SM-2 one-week default-browser test (percentages are meaningless at solo-user session counts). The skeleton is exempt as dev-iteration software. | P1 | SM-2 |
| NFR-5 | Egress audit | Capture a full browse+login+autofill session via a filtering proxy (per Spike A's follow-up mini-spike) and classify every outbound connection as *page-initiated* (attributable to a navigated document or its subresources) or *shell/shim-originated*. **100%** of shell/shim-originated connections match the FR-22 allowlist; **zero** unexplained shell/shim hosts. Page-initiated traffic is recorded but not gated. | P0 | FR-22 |
| NFR-6 | Shim re-validation turnaround | The FR-25 re-grep + triage completes within **1 business day** of a new Pass release being noticed. | P1 | FR-25 |
| NFR-7 | Vault-unlock-to-autofill latency | Once Pass reports unlocked, dropdown fill completes within **1 s (max of 10 trials)** of user click on a suggestion (excludes Pass's own crypto time). Measured at skeleton; gates at v0.x. | P1 (measured at P0 stage) | FR-15 |
| NFR-8 | Zero plaintext credentials in artifacts | Two-part verification, neither of which requires the agent to know a secret: (a) **structural review** — no Muninn code path logs message-broker payloads, storage contents, or pasteboard data; (b) **Calvin personally** searches logs/crash reports for substrings of his own credentials before each milestone gate. Zero findings on both. | P0 | FR-21 |
| NFR-9 | Content-blocking effectiveness | Compiled `WKContentRuleList` blocks **≥ 95% of *tracker* requests** on a reference tracker test page (not 95% of all requests — the page must still work), with zero compile errors. | P1 | FR-20 |
| NFR-10 | Background-host resource ceiling | Hidden background host ≤ **150 MB RSS** steady-state; no unnecessary App Nap exemption (battery sanity on Apple Silicon). | P1 | FR-7 |

---

## 8. Non-Goals

| Non-goal | Phase it becomes in-scope (if ever) |
|---|---|
| Tab strip / shell visual polish (Arc-like animation, spaces, split view) | Post-v0.x "polish" phase; a *minimal* tab model (FR-2/FR-3) is v0.x, not the skeleton. |
| Sync layer (cross-device tab/history sync, Scala service) | Future "Sync" phase — architecture explicitly deferred until the skeleton ships (Open Question 3). |
| Content blocking (`WKContentRuleList`) | v0.x (FR-20, P1) — not in the MVP walking skeleton. |
| Save-login prompt | v0.x (FR-16, P1) — not in the MVP walking skeleton. |
| iOS | Not committed to any phase in this PRD; strategic option only (`product-brief.md`). |
| General WebExtension platform (extensions beyond Pass) | Permanent non-goal — D2's consequence is "no extension platform," a purpose-built shim only. |
| Windows / Linux support | Permanent non-goal — Apple-native is core to the vision (D2, D3). |
| Mac App Store distribution | Not in MVP/v0.x (Open Question 5 resolution: signed + notarized direct download); revisit at 1.0. |
| `nativeMessaging` (Pass desktop app lock-state integration) | Deferred indefinitely (Spike B Tier 3 skip); FR-12 is a no-op stub only. |
| Biometric **vault** unlock (JTBD-3) | Deferred past v0.x — see OQ-6; FR-23's app-level gate is not this feature. |
| History, bookmarks, find-in-page | P2, unscheduled — SM-2's one-week test tolerates their absence (§6.8 note). |

---

## 9. MVP Scope Cutline — The Walking Skeleton

The walking skeleton is defined as exactly the following **P0** requirements, and no others:

**FR-1, FR-4, FR-5, FR-7, FR-8, FR-9, FR-10, FR-11, FR-13, FR-14, FR-15, FR-19, FR-21, FR-22, FR-25**

Risk-burn order is itself a requirement (per Spike B): implementation and validation SHALL proceed in this order, not in parallel across all three:

| Order | Risk (Spike B) | Primary FRs | Gate |
|---|---|---|---|
| 0 (pre-req) | — | FR-25 | Re-grep inventory complete and triaged before any shim code is written. |
| 1 | Auth-fork login flow | FR-1, FR-4, FR-5, FR-7, FR-10, FR-11, FR-13 | Manual login at `account.proton.me` is picked up by the shim under the **canonical** extension identity. If this fails, stop — nothing downstream is testable; escalate to the D4 fallback ladder (`decisions.md`): (1) fix within shim scope, (2) Pass web app in a pinned tab, (3) Chrome-style CEF window. |
| 2 | Dropdown-iframe mechanics under strict CSP | FR-8, FR-9, FR-14, FR-15 | Field icon + dropdown render and fill on the one chosen real site. |
| 3 | Service-worker global-scope assumptions | FR-7 (global-scope audit clause) | Audit log shows zero untriaged `ServiceWorkerGlobalScope` API usage in `background.js`. |

All other FRs (P1/P2) are explicitly **out of scope** for the walking skeleton and belong to the v0.x daily-driver phase or later; see §8.

**NFR gating at the skeleton:** only NFR-5 (egress audit) and NFR-8 (zero plaintext credentials) gate the skeleton. The latency/footprint NFRs (NFR-1, NFR-2, NFR-7) are measured and recorded at the skeleton but gate at v0.x — the skeleton's purpose is risk burn-down, not performance tuning.

---

## 10. Success Metrics (with counter-metrics)

| ID | Success metric | Counter-metric (guards against gaming) |
|---|---|---|
| SM-1 | The three risk flows (login pickup, dropdown/autofill, background-host stability) pass end-to-end on the **real Proton production extension bundle**. | Must be validated under the **canonical** (CRX-key-pinned) extension identity, not a path-derived side-loaded ID (Spike A finding) — a pass under the wrong ID doesn't count. |
| SM-2 | Calvin uses Muninn as his default browser for **one full week** without reaching for Safari for a Pass-related reason. Preconditions: the full P1 daily-driver set, including FR-27 (navigation), FR-28 (downloads), and FR-29 (default-browser registration). | NFR-4 (at most 1 crash that week) must hold simultaneously, and autofill must be exercised on a **variety** of distinct sites (not just `proton.me`) during that week — avoid gaming the week via avoidance/narrow use. |
| SM-3 | An egress audit of a full session shows **only** allowlisted hosts (FR-22, NFR-5). | The parity canary (FR-25) must stay green — a clean audit achieved by silently breaking or disabling shim network calls (e.g., login pickup) does not count. |
| SM-4 | Popup and autofill latency targets (NFR-1, NFR-7) are met. | Correctness (FR-13/14/15 acceptance criteria) takes precedence — latency must not be hit by skipping vault-state verification or error handling. |

---

## 11. Assumptions & Dependencies

- **AS-1** — Proton continues shipping a Safari (WebKit) build profile for Pass; if discontinued, D2's premise must be revisited (`decisions.md`).
- **AS-2** — `ProtonMail/WebClients` remains open source and publicly accessible for the FR-25 re-grep gate.
- **AS-3** — The Spike B inventory (Pass v1.38.2, 2026-07-11) may drift before implementation starts; FR-25 is the explicit mitigation, not an assumption of stability.
- **AS-4** — Apple continues to support the WKWebView primitives this PRD depends on (`WKContentWorld`, `WKURLSchemeHandler`, `WKScriptMessageHandler`) at current API stability through the PRD horizon.
- **AS-5** — Calvin remains personally available to perform all human-gated login/unlock/GUI-launch actions (ground rules 1 and 2); no automated credential handling will ever be introduced as a workaround.
- **AS-6** — Development and validation target a single machine (Calvin's Mac, macOS 26.x, Apple Silicon); no fleet/CI hardware matrix is assumed for v0.x.
- **AS-7** — Signing/notarization credentials (Apple Developer Program membership) are assumed obtainable for the Open Question 5 distribution resolution; not yet confirmed as an active enrollment — flag if absent.
- **AS-8** — A production Proton Pass extension bundle (the shipped Safari/Chrome artifact, v1.38.2 at spike time) can be obtained and refreshed for embedding in Muninn; the acquisition/update mechanism (store download, WebClients build, or vendored copy) is an architecture-phase decision. FR-26 records the version; nothing in this PRD covers redistribution licensing — flag for the trademark/legal TODO in `decisions.md` D1 if Muninn is ever distributed publicly.

---

## 12. Open Questions (from `product-brief.md`) — Proposed Resolutions

**OQ-1 — v0.x shell scope.**
*Question:* What is the minimal tab model worth building before daily-driving?
*Proposed resolution (pending Calvin):* A minimal multi-tab model — tab strip or switcher plus session restore (FR-2, FR-3) — is the smallest thing that enables daily-driving. Arc-like visual polish (spaces, animated tab groups, split view) is explicitly deferred past v0.x (§8).

**OQ-2 — Save-login parity.**
*Question:* Safari's profile lacks `webRequest`; accept Proton's degraded heuristics or build a native one?
*Proposed resolution (pending Calvin):* Accept Proton's existing Safari-profile heuristic as-is for MVP and v0.x (FR-16). A native heuristic (using signals the shim uniquely has, e.g. native form-submit observation) is a possible later enhancement, not a requirement — it adds surface area disproportionate to the gain while daily-driving with a single user.

**OQ-3 — Sync layer.**
*Question:* Protocol/hosting for cross-device sync — self-hosted Scala service? Proton Drive-backed? Defer until the skeleton ships?
*Proposed resolution (pending Calvin):* Defer all sync architecture until the walking skeleton ships and daily-driver v0.x is stable. Sync is a hard non-goal for this PRD (§8); JTBD-5 remains recorded as a future placeholder to be scoped in its own PRD/architecture cycle once there is a second device or a stable v0.x to sync from.

**OQ-4 — Content blocking.**
*Question:* `WKContentRuleList` source lists and update mechanism?
*Proposed resolution (pending Calvin):* EasyList + EasyPrivacy compiled into a `WKContentRuleList`, with a manual update command (re-fetch + recompile on demand) for v0.x (FR-20). Automatic background updates are deferred — they'd need their own egress-allowlist and scheduling design, disproportionate to v0.x scope.

**OQ-5 — Distribution.**
*Question:* Signed + notarized direct download vs. Mac App Store?
*Proposed resolution (pending Calvin):* Signed + notarized direct download for v0.x. The Mac App Store's sandbox model risks both the shim's WKWebView/scheme-handler techniques and default-browser eligibility, and re-litigating that risk mid-build is expensive. Revisit the Mac App Store at 1.0. The sandbox-vs-shim investigation itself is flagged as an **architecture-phase task**, not resolved here.

**OQ-6 — Biometric vault unlock (JTBD-3) — added by review.**
*Question:* JTBD-3 asks for Touch ID / Apple Watch **vault** unlock, but no requirement in this PRD delivers it: FR-14 is Pass's own in-popup unlock, and FR-23 is only an app-level content gate. How does the vault ever unlock "the Apple way"?
*Proposed resolution (pending Calvin):* Defer past v0.x, honestly recorded rather than silently dropped. The plausible paths are (a) Pass's extension-side biometric/PIN unlock options, if its Safari-profile build exposes them in our host environment — investigate during the skeleton; or (b) the deferred `nativeMessaging` desktop-app integration (FR-12). Neither is required for the skeleton or the SM-2 week; scope it when v0.x is stable.

---

## 13. Approval

**HUMAN GATE — Calvin Ference**

> *(verbatim verdict and timestamp to be recorded here upon review)*

Status: **Awaiting approval.**
