# CLAUDE.md — Muninn Browser

Muninn is a privacy-first, Apple-native macOS browser with a fully custom shell, built on **WKWebView** with a purpose-built **Proton Pass API shim** (no general extension platform). Swift/AppKit for shell + shim runtime; Scala reserved for the future sync/service layer.

## Where this project stands (artifact state)

Analysis, Planning, and Solutioning (architecture) are **complete and approved** (PRD + roadmap: 2026-07-11 21:14 EDT; architecture + ADRs: 2026-07-11 22:55 EDT). The artifacts in this directory are the record:

- `product-brief.md` — vision, MVP (walking skeleton), constraints, open questions. **Start here.**
- `decisions.md` — locked decisions (name, engine, language split, fallbacks). Do not re-litigate without new evidence.
- `research/spike-a-results.md` — engine spike (CEF/JCEF ruled out; signed off 2026-07-11).
- `research/spike-b-proton-pass-api-inventory.md` — the shim spec (Proton's Safari build profile; ~45 methods; Tier 1/2/3 breakdown; ordered risk list).
- `prd.md` — v0.1 **APPROVED** (2026-07-11): FR-1…29, NFR-1…10, MVP cutline (§9), resolutions to all open questions (§12). The locked "what".
- `roadmap.md` — v0.1 **APPROVED**: milestones M0–M3 + Sync horizon, epics E1–E12, full FR→epic traceability, dependency DAG. The plan of record.
- `architecture.md` — v0.1 **APPROVED**: HLD (closed-microkernel modular monolith, C4 diagrams, 9-risk table, 3 ratified deviations in §10).
- `adr/ADR-001…008` — all **Accepted**; ADR-002 and ADR-006 carry open spikes (S5: pktap eproc + proxy routing, gates E8; S6: scheme-request initiator identification, gates E4). Spikes S1/S2 gate E3/E6 (see ADR-001/-005).
- `openspec/changes/architecture-and-adrs/` — the completed Solutioning change (research evidence under `research/`).

**M0 is EXITED** (Calvin, 2026-07-11 23:35 EDT — see `roadmap.md` §6): the Xcode scaffold builds/launches, the FR-25 gate is satisfied (`research/regrep/2026-07-11.md`; new API `runtime.getFrameId` → Tier 2/E5), and the Pass bundle v1.38.0 is vendored (`vendor/pass-extension/`, `tools/refresh-pass-bundle.sh`).

**E2+E3 are built (change `e2-e3-shim-core`): the shim core + background host.** S1 is retired — Proton's real v1.38.0 `background.js` boots CLEAN in the DedicatedWorker substrate (ADR-005 refined 2026-07-12: background.js runs in a Worker inside the hidden WKWebView because it uses `importScripts`). 16 XCTests green; refute-review blockers all fixed. Ports deferred to E6 (need a 2nd context). **E3-hardening + S2 are done (change `e3-hardening-s2`).** Timer throttling FIXED with a **public** lever (`WKPreferences.inactiveSchedulingPolicy = .none`) — bisect: 125/120 ticks vs the 4/120 default baseline; zero private API in the shipping path (`research/nfr10-residency-2026-07-12-post-mitigation.md`). S2 spike GO: the shim is provably confined to an isolated `WKContentWorld` — page MAIN world has no `chrome`/`browser`/broker handler; the account app's postMessage fallback is selected by corollary (`research/s2-fork-fallback-2026-07-12.md`). Root-caused via the webkit-developer agent (the throttle is RunningBoard suspension + App Nap, not DOM-timer throttling; an off-screen window was refuted). 22 XCTests green.

**Two carries into E6:** (1) the host now uses a dedicated `WKWebsiteDataStore` (for the per-process throttle latch) — verify the auth-fork handshake doesn't depend on a shared cookie store with `*.proton.me` tabs; (2) the native→content inbound push path is unwired (login uses the postMessage fallback, not `onMessageExternal`, so out of S2 scope — E5/E6 wire it).

**E6 (auth-fork login) is CHECKPOINTED at a precise, non-D4 blocker** (`research/e6-auth-fork-2026-07-17.md`). Built + green (23 tests): the minimal navigable shell (`AppShell`), the cross-context request/response **message bus** (page `runtime.sendMessage` → host worker `onMessage` → `sendResponse`, under canonical id), and the fork trigger (`runtime.onInstalled` → `background.js` `tabs.create` → the onboarding URL, now wired to the shell). Two live login attempts (Calvin at the keyboard, no credentials touched): the onboarding page loads with correct fork params, but the account app reports **"Proton Pass is missing permissions"** — because we inject only `fork.js`, not `orchestrator.js` (the general content script the account app's extension-detection depends on). **This couples E6 to E5.**

**Next step in the pipeline: E5 (general injection — `orchestrator.js` + frame registry, FR-9, incl. `runtime.getFrameId`), subsuming the minimal `ForkBridgeInjector`), then re-attempt the E6 gate.** Also pending: E4 (scheme handler / S6). Honor the ratified deviations (FR-12 stub is skeleton scope; FR-13 flows via the vendored fork.js). Not D4 — engine/boot/injection/bus all work. Don't gold-plate — solo passion project.

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
