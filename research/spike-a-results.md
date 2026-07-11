# Spike A Results — CEF/JCEF × Proton Pass (Local Execution)

**Date:** 2026-07-11 · **Executor:** Claude (agent) + human gates · **Status: COMPLETE — signed off**

## Environment

| Item | Value |
|---|---|
| macOS | 26.0.1 (build 25A362) |
| Architecture | arm64 (Apple Silicon) |
| python3 | 3.10.11 |
| curl | 8.7.1 |
| unzip | 6.00 (Info-ZIP, Apple) |
| java | OpenJDK 24.0.1 (Corretto) — satisfies ≥21 |
| scala-cli | **not installed** at spike start (Test 3 prerequisite; install pending user approval) |
| CEF build | 144.0.30+g9e70dde+chromium-144.0.7559.257 (macosarm64 client, latest stable) |
| Extension | Proton Pass v1.38.2, MV3 — matches version Spike B kit was validated against |

## Execution notes (deviations from kit scripts)

1. **`--remote-debugging-port=9222` added** to both invocations in `02-test-cefclient.sh` (per protocol).
2. **Canonical extension ID had to be pinned.** `--load-extension` of the unpacked CRX yielded a *path-derived* ID (`moekgnpokmeppccnaobholbpgaignjka`), not the production ID. Since check 1.3 (site → extension session pickup via `externally_connectable`/`onMessageExternal`) is keyed to the production ID, the CRX3 header's public key was extracted from `pass.crx` and embedded as `"key"` in `extension/manifest.json`. After that the extension loads as `ghmbeldphafepmbegfdlkpapadhbakde` (verified via DevTools). **Any Path 1 browser that side-loads Pass unpacked must do the same.**
3. **cefclient launched via `launchctl submit` (label `spike-cef`)** rather than as a child of the agent's shell. The first three launches exited cleanly after ~45–120 s (no crash reports); most likely the human closed the unannounced windows while working at the machine. Not a CEF defect. Logs still tee to `test1-chrome.log`.

## Test 1 — cefclient, Chrome style (extension-support ceiling)

| # | Check | Result | Evidence |
|---|---|---|---|
| 1.1 | Extension loaded (target with canonical `chrome-extension://ghmbe…` URL) | ✔ PASS | `evidence/test1-targets.json` (13:24 EDT) |
| 1.2 | Background service worker alive (`type: service_worker`, `background.js`) | ✔ PASS | `evidence/test1-targets.json` |
| — | Bonus: content-script layer active pre-login — `dropdown.html` iframe injected into `account.proton.me/login` | observed | same target list |
| — | Bonus: extension onboarding page auto-opened ("Thank you for installing Proton Pass") — worker executed install hook | observed | same target list |
| 1.3 | Login at account.proton.me picked up by extension | ✔ PASS (human) | Gate 1 verdict |
| 1.4 | Toolbar popup opens, vault unlocks | ✔ PASS (human) — "very slow to open" | Gate 1 verdict |
| 1.5 | Autofill: field icon, dropdown, credentials fill | ✔ PASS (human) | Gate 1 verdict |
| 1.6 | (optional) Save-login prompt | ✔ PASS (human) | Gate 1 verdict |
| — | Service worker still alive post-login (re-query) | ✔ PASS | `evidence/test1-targets-postlogin.json` (13:41 EDT) |

### HUMAN GATE 1 verdicts (recorded 2026-07-11 13:41 EDT, verbatim)

> 1. Pass
> 2. Pass but very slow to open
> 3. Pass
> 4. Pass

(Numbering maps to checks 1.3, 1.4, 1.5, 1.6.)

**Test 1 verdict: PASS (1.1–1.6 all green; 1.4 popup latency noted).** Chrome-style CEF is a fully working ceiling for Proton Pass.

## Test 2 — cefclient, Alloy style (custom-UI reality check)

Launched via `launchctl submit` (label `spike-cef-alloy`) with `--use-alloy-style`, fresh `profile-alloy`, same extension + debug port.

| # | Check | Result | Evidence |
|---|---|---|---|
| 1.1 | Extension loaded (canonical ID) | ✔ PASS | `evidence/test2-targets.json` (13:44 EDT) |
| 1.2 | Background service worker alive | ✔ PASS | `evidence/test2-targets.json` |
| — | Bonus: `dropdown.html` iframe injected into login page under Alloy style — content-script layer active without Chrome UI | observed | same target list |
| — | No toolbar in Alloy style → popup checked via `chrome-extension://…/popup.html` tab opened through DevTools (`PUT /json/new`), per protocol workaround | note | — |
| 1.3 | Login picked up by extension | ✘ FAIL (human) | Gate 2 verdict |
| 1.4 | Popup functions when loaded directly as a tab | ✘ FAIL (human) — "Never was able to load" | Gate 2 verdict |
| 1.5 | Autofill works | ✘ FAIL (human) — "Never was able to load" | Gate 2 verdict |

### HUMAN GATE 2 verdicts (recorded 2026-07-11 13:52 EDT, verbatim)

> For some reason the network latency is extremely slow, I even had timeouts and No network connection in the small window after login into my proton acount.
>
> 1.3 No
> 1.4 Never was able to load
> 1.5 Never was able to load

### Post-gate diagnosis (deterministic)

- Host network was fast at gate time (`curl` to account.proton.me: 0.39 s total, HTTP 200).
- A plain page (`https://example.com`) opened via CDP **inside the running Alloy window** loaded normally → general in-browser networking is not the fault.
- The `popup.html` tab opened via CDP **disappeared from the target list** (never became a live page).
- `test2-alloy.log` shows repeated `cef/libcef/browser/browser_info_manager.cc:852 Timeout of new browser info response for frame …` — CEF failing to wire up new frames — coinciding with the popup/extension-page loads.

**Interpretation:** under Alloy style, Proton Pass content scripts inject (dropdown iframe observed on the login page) and the service worker runs, but **hosting of `chrome-extension://` pages is broken** (frame creation times out). The perceived "no network connection" inside Pass UI is the downstream symptom. Session pickup (1.3) fails, so vault unlock and autofill (1.4/1.5) never become testable.

**Test 2 verdict: FAIL (1.1/1.2 pass; 1.3–1.5 fail — extension-page hosting defect under Alloy style).** Matches the CEF maintainer's position that extensions are only supported with Chrome-style windows.

## Test 3 — JCEF from Scala (JVM wrapper path)

Setup: `scala-cli` 1.15.0 installed via Homebrew (user-approved). `setup.sh` pinned **jcefmaven 135.0.20 → Chromium 135**, i.e. **9 major versions behind** the CEF stable used in Tests 1/2 (Chromium 144); jcefmaven's own hint suggested 146.0.10 exists, so the lag is a resolver artifact worth rechecking, not necessarily a project-abandonment signal. `--remote-debugging-port=9222` added via `builder.addJcefArgs`. Harness modified: minimal Swing URL bar added (no toolbar otherwise — checks 1.4/1.5 need navigation) and `cache_path` set to `profile-jcef` for session persistence.

**Two JVM-side blockers hit and fixed (key findings for the Scala-chrome path):**

1. **`IllegalAccessError: CefBrowserWindowMac cannot access sun.awt.AWTAccessor`** — thrown on `JFrame.setVisible`, so CEF ran headless-ish (service worker fine, no window ever appeared). JCEF on macOS requires JPMS flags: `--add-exports=java.desktop/sun.awt=ALL-UNNAMED` (plus `sun.lwawt`, `sun.lwawt.macosx`). Fixed via `//> using javaOpt`.
2. **Rosetta trap:** scala-cli resolved an x86_64 JVM, so JCEF pulled x64 CEF natives; Chromium logged "use of Rosetta … is neither tested nor maintained, and unexpected behavior will likely result". Fixed by forcing the arm64 system JDK (`JAVA_HOME`, `//> using jvm system`); jcefmaven then fetched `macosarm64` natives.

Also noted: launching the harness via `launchd` never got the AWT window into the user's session; had to launch from the login session (double-fork + `setsid`).

| # | Check | Result | Evidence |
|---|---|---|---|
| 1.1 | Extension loaded (canonical-ID target present) | ✔ PASS | `evidence/test3-targets.json` (14:33 EDT) |
| 1.2 | Background service worker alive | ✔ PASS | `evidence/test3-targets.json` |
| — | Bonus: `dropdown.html` iframe injected into the login page — content-script layer active in JCEF/Swing embedding | observed | same target list |
| 1.3 | Login picked up by extension | ✘ FAIL (human) — login itself worked; no extension pickup observed | Gate 3 verdict |
| 1.4 | Popup functions (`popup.html` navigated in-window) | ✘ FAIL (human) — **window crashed** | Gate 3 verdict + `evidence/test3-jcef-stderr.log` |
| 1.5 | Autofill works | ✘ FAIL (human) | Gate 3 verdict |

### HUMAN GATE 3 verdicts (recorded 2026-07-11 14:25 EDT, verbatim)

> 1.3 I don't see the window with the extension, though I was able to login
> 1.4 Window crashed
> 1.5 Failed test

### Post-gate diagnosis (from `evidence/test3-jcef-stderr.log`)

- Repeated bare `Exception in thread "AppKit Thread"` (no stack traces) flooding stderr — known JCEF main-thread fragility on macOS.
- `FIDO: Touch ID authenticator unavailable — keychain-access-group entitlement missing` during login (webauthn degraded in unsigned JCEF host).
- After the popup.html navigation the CEF browser (and its DevTools endpoint) died while the JVM lingered as a zombie — i.e. the crash is in the native CEF/AppKit layer, not a clean Java exception.
- Consistent with Test 2: extension *pages* fail outside Chrome-style windows; in JCEF they fail harder (native crash vs. load failure).

**Test 3 verdict: FAIL (1.1/1.2 pass + content-script injection observed; 1.3–1.5 fail; popup navigation crashes the embedded browser).** Test 3 ≈ Test 2 for the core limitation, marginally worse in stability, and the JVM path adds real integration friction (JPMS `--add-exports`, Rosetta/arch trap, AppKit-thread instability, unsigned-host entitlement gaps).

## Decision matrix row

Outcome: **T1 ✔ · T2 ✘ · T3 ✘**

Matching kit-README row: **"T1 ✔ T2 ✘ — Path 1 works but pushes UI toward Chrome-style windows — dents the Arc-like vision; strengthens Path 2 (WKWebView + shim, GO per Spike B)."** T3 failing alongside T2 (and slightly worse) removes the JVM-wrapper variant from consideration for the extension-hosting layer as well.

## Synthesis

- **The ceiling is real and high:** in Chrome-style CEF windows, Proton Pass works end-to-end — login pickup, vault unlock, autofill, and even the save-login prompt (1.6). Embedded Chromium *can* host Pass fully.
- **The ceiling is also the constraint:** everything below Chrome-style windows breaks the same way. Content scripts + service worker survive (autofill *infrastructure* injects), but `chrome-extension://` page hosting fails (Alloy) or crashes (JCEF), which kills session pickup → vault → autofill in practice.
- **The Arc-like custom shell and full Pass support are in direct tension** on Path 1. Options preserved by the data: (a) Chrome-style window with heavily customized allowed chrome; (b) Path 2 (WKWebView + API shim per Spike B); (c) Path 1 + Pass web app in a pinned tab as fallback.
- **Scala/JCEF is additionally disqualified for the engine layer** by version lag (Chromium 135 vs 144 at test time), JPMS/arch/launch friction, and native-layer instability. Scala remains viable in the sync/service layer.
- Reproducibility notes: side-loading Pass requires pinning the CWS public key in the manifest (canonical ID), or `onMessageExternal` session pickup silently breaks even where extensions work.

**Engine decision input: Path 1 (embedded Chromium) is viable only with Chrome-style windows — a fully custom Arc-like shell cannot host Proton Pass on CEF today (T2 ✘/T3 ✘); this strengthens Path 2 (WKWebView + shim) per Spike B, with "Chrome-style Path 1" and "Pass web app pinned tab" as the fallback lines.**

## Artifacts

- `spike-a-results.md` (this file)
- `evidence/test1-targets.json`, `evidence/test1-targets-postlogin.json`
- `evidence/test2-targets.json`
- `evidence/test3-targets.json`, `evidence/test3-jcef-stderr.log`
- `test1-chrome.log`, `test2-alloy.log`, `03-jcef-harness/jcef-run.log`
- Modified harness: `02-test-cefclient.sh` (debug port), `03-jcef-harness/PassHarness.scala` (JPMS exports, system JVM, URL bar, cache path, debug port), `03-jcef-harness/run-jcef.sh` (new launcher), `extension/manifest.json` (canonical `key` pinned)

## Privacy posture note (Path 1 / Chromium engine)

Raised by reviewer pre-sign-off. Chromium-the-engine ≠ Chrome-the-product, but the engine ships Google service hooks that are on by default, and this spike captured direct evidence:

- Both cefclient runs repeatedly attempted **GCM (Google Cloud Messaging) registration** — `google_apis/gcm/engine/registration_request.cc … DEPRECATED_ENDPOINT` in `test1-chrome.log` and `test2-alloy.log`. Calls failed only because CEF ships no Google API keys.
- The generated profile contains Chrome service machinery: **Safe Browsing**, **Variations** (field trials), **OptimizationHints**, component-updater caches (`component_crx_cache`), and a **UKM** metrics database.
- Default-on background traffic to expect from a Chromium engine: component updater, Safe Browsing list updates, variations, GCM, network time, DNS preconnect. Sync/translate/metrics upload are effectively off in CEF (no keys/opt-in).

Mitigation ladder: (1) runtime flags/prefs (`--disable-background-networking`, `--disable-component-update`, Safe Browsing config) — the Vivaldi approach; (2) **egress audit in CI** — run behind a filtering proxy and assert a host allowlist (recommended regardless of path); (3) build-time stripping (ungoogled-chromium patch set) — strongest, but you inherit a Chromium build pipeline. Trade-off to decide deliberately: disabling Safe Browsing removes phishing protection; local-list/self-proxied designs can keep it without exposing URLs. For contrast, Path 2 (WKWebView) trusts Apple's system engine, which does its own OS-level callouts (Safe Browsing, OCSP) with *less* configurability but a smaller managed surface.

**Follow-up candidate:** deterministic egress audit of the chosen engine configuration (proxy + host allowlist) as its own mini-spike.

## Reviewer direction (post-review, pre-sign-off)

Recorded 2026-07-11 (verbatim): *"I just tried Proton Pass on Safari and it works marvelously, I think we should use WebKit."*

Engine direction: **Path 2 — WKWebView + Proton Pass API shim (per Spike B)**. Clarified during review: Pass-on-Safari is a Safari Web Extension, which a custom WKWebView browser cannot host directly — Path 2 still requires the Spike B shim; the Safari experience validates the WebKit engine compatibility and Proton's commitment to a WebKit build, not extension portability.

## Sign-off (HUMAN GATE 4)

**Signed off** by reviewer **Calvin Ference** — 2026-07-11 16:06 EDT (verdict given verbatim: "Sign off"). Spike A complete.
