# CLAUDE.md — Muninn Browser

Muninn is a privacy-first, Apple-native macOS browser with a fully custom shell, built on **WKWebView** with a purpose-built **Proton Pass API shim** (no general extension platform). Swift/AppKit for shell + shim runtime; Scala reserved for the future sync/service layer.

## Where this project stands (artifact state)

Analysis phase is **complete**; Planning artifacts are **drafted, awaiting Calvin's approval gate**. The artifacts in this directory are the record:

- `product-brief.md` — vision, MVP (walking skeleton), constraints, open questions. **Start here.**
- `decisions.md` — locked decisions (name, engine, language split, fallbacks). Do not re-litigate without new evidence.
- `research/spike-a-results.md` — engine spike (CEF/JCEF ruled out; signed off 2026-07-11).
- `research/spike-b-proton-pass-api-inventory.md` — the shim spec (Proton's Safari build profile; ~45 methods; Tier 1/2/3 breakdown; ordered risk list).
- `prd.md` — v0.1 DRAFT (2026-07-11): FR-1…29, NFR-1…10, MVP cutline (§9), proposed resolutions to all open questions (§12). Passed checker review + mechanical ID/cutline verification. **Awaiting Calvin's approval (§13).**
- `roadmap.md` — v0.1 DRAFT: milestones M0–M3 + Sync horizon, epics E1–E12, full FR→epic traceability, dependency DAG. Inherits the PRD's pending gate (§6).

**Next step in the pipeline: HUMAN GATE — Calvin reviews/approves `prd.md` (§13) and `roadmap.md` (§6)** (record verdicts verbatim with timestamps). After approval: Solutioning — architecture + ADRs (solution-architect), then per-epic OpenSpec changes with stories, then the walking skeleton (E1 first: git init, Xcode scaffold, FR-25 re-grep gate). Don't jump to code before the architecture exists as a file; don't gold-plate either — this is a solo passion project, not enterprise compliance.

## Ground rules (non-negotiable)

1. **Never handle Proton credentials.** No asking for, reading, storing, or typing passwords, TOTP codes, or vault contents. All login/unlock actions are performed by Calvin at explicit human gates. Never capture logs/screenshots that would contain credentials or vault data.
2. **Warn Calvin in chat *before* launching anything that opens a GUI window** (apps, test harnesses, WKWebView shells). He works on this Mac and closes unannounced windows — that invalidated three test runs in Spike A. For interactive test gates, launch only when he confirms he's ready.
3. **Human gates at phase transitions.** Calvin approves the PRD, the architecture, and each milestone. Record his verdicts verbatim with timestamps in the relevant artifact.
4. **Execute, don't opine.** Reviews and checks must run the code/tests/flows and cite output. Where a check can be deterministic (DevTools endpoint, log parsing, script), do that before asking a human to eyeball it.
5. Ask before Homebrew installs or any purchase/registration (domains are pending human actions — see `decisions.md`).

## First implementation milestone (after PRD + architecture)

The **walking skeleton**: one window, one WKWebView tab, shim runtime up — login at account.proton.me → vault unlock → autofill on one real site. This retires Spike B's three ordered risks:

1. Auth-fork login flow (`onMessageExternal` bridge injected on `*.proton.me`) — test end-to-end **first**; if login can't complete, nothing else matters.
2. Dropdown-iframe mechanics (custom-scheme iframe in arbitrary pages, CSP interactions).
3. Service-worker global-scope assumptions in `background.js`.

## Key technical facts (from the spikes — trust these, they were measured)

- The shim targets **Proton's Safari build profile**: `storage`, `alarms`, `runtime` messaging + `getURL`, `tabs`, `action`, `windows`, `permissions` (stub), `scripting`, `webNavigation`, `clipboardWrite`. **Skip** `webRequest`, `offscreen`, `privacy`, `commands` — Proton's own Safari build excludes them.
- Four Tier-2 subsystems are the real work: background service-worker host (hidden WKWebView/JSContext — keep alive forever, no MV3 suspend semantics), `WKURLSchemeHandler` for extension resources + web-accessible-resource semantics, `WKContentWorld`/`WKUserScript` injection + frame registry (from `WKNavigationDelegate`/`WKFrameInfo`), and the message broker (`WKScriptMessageHandler` + `evaluateJavaScript`).
- Re-run Spike B's grep inventory against `ProtonMail/WebClients` before writing shim code — it was taken 2026-07-11 vs Pass v1.38.2 and Proton ships often. Their Safari build is the permanent canary for shim parity.
- If the extension is ever side-loaded in a Chromium context (fallback line 3): the CRX public key must be pinned as `"key"` in `manifest.json` or the site→extension login handshake silently breaks (path-derived vs canonical extension ID).
- WKWebView niceties confirmed relevant: Apple Pay JS **disables script injection on active pages** (shim must tolerate suspension on checkout pages); `WKContentRuleList` for blocking; `LocalAuthentication` with `...OrWatch` for vault unlock; `ASAuthorization` for passkeys.

## Naming

Product: **Muninn** (App Store listing: "Muninn Browser"). See `decisions.md` for the availability sweep and pending human actions (defensive domains, trademark counsel).
