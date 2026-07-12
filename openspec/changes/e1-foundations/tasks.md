# Tasks: e1-foundations

## 1. Repo hygiene

- [x] 1.1 Add `.gitignore` (Xcode/DerivedData noise, `.DS_Store`, `*.pcapng`, build products)

## 2. Xcode scaffold (project-scaffold spec)

- [x] 2.1 Create the Muninn Xcode project: Swift/AppKit app target, programmatic `NSApplicationDelegate` + single blank `NSWindow`, no storyboards
  — objectVersion 77 (synchronized folder), Swift 6, ad-hoc signing (ADR-003), "Embed About Metadata" script phase for FR-26 resources.
- [x] 2.2 Verify clean-checkout build: `xcodebuild -scheme Muninn build` from a pristine clone in a temp dir
  — BUILD SUCCEEDED (working tree; pristine-clone re-verification folded into 6.1 once committed).
- [x] 2.3 **[HUMAN GATE — ground rule 2]** Warn Calvin, wait for confirmation, launch the app once: one blank window appears, quits cleanly
  — Done 2026-07-11: Calvin confirmed readiness, launch performed, verdict **"Both pass"** (blank window + About panel values v1.38.0 / 2026-07-11.md — also closes 5.2's visual half). App quit cleanly.

## 3. Pass bundle vendoring (pass-bundle-vendor spec)

- [x] 3.1 Verify Proton Pass for Safari.app is installed and locate the appex `Resources/`; record the current extension version
  — Installed; extension v1.38.0; web subset ~20 MB after excluding Proton-native `*.bundle` payloads (~68 MB).
- [x] 3.2 Write `tools/refresh-pass-bundle.sh` (detect version, extract web-bundle subset, write `MANIFEST.lock` with sha256, print manifest diff + FR-25 reminder; loud failure if app missing)
- [x] 3.3 Run it for the initial extraction → `vendor/pass-extension/<version>/` + lockfile; verify integrity scenario (sha256 recompute; manifest version match; `fork.js` declared for account.proton.me)
  — All scenarios pass: sha256 MATCH; versions equal; fork.js declared for `https://account.proton.me/*`; wasm under `assets/wasm/` (WAR-listed `<all_urls>` — relevant to S6); no-op-on-same-version verified.

## 4. Parity-canary gate (parity-canary spec)

- [x] 4.1 Write `tools/regrep-inventory.sh` (shallow-clone WebClients main → Spike B grep inventory → dated artifact with diff-vs-baseline table + triage placeholder; non-zero exit on clone failure)
  — Plus `tools/regrep-baseline.txt` (the checked-in Spike B surface; updated to post-triage state after the first run).
- [x] 4.2 Run it; produce `research/regrep/<date>.md`
  — `research/regrep/2026-07-11.md` @ WebClients `ea9021f3`; Safari manifest still excludes commands/webRequest/privacy/offscreen.
- [x] 4.3 Triage every diff entry (Tier 1/2/3 disposition) in the artifact — zero untriaged entries; if the diff is large, stop and flag before E2+ is unblocked
  — 6 NEW entries triaged: 5 are Tier-3 skips/baseline omissions; **1 genuinely new API: `runtime.getFrameId` → Tier 2, assigned to E5's FrameRegistry**. Gate SATISFIED; architecture unaffected.
- [x] 4.4 Cross-check the re-grep against the *vendored* bundle version (not just WebClients main) — note any version skew in the artifact
  — Vendored 1.38.0 vs main 1.38.2: the predicted MAS patch-level lag (§8 risk 5); Safari permission profile identical, bundle valid.

## 5. FR-26 display mechanism (project-scaffold spec)

- [x] 5.1 Add the About/debug panel: menu item → window rendering `MANIFEST.lock` fields + newest `research/regrep/` date (lockfile copied into the app bundle at build time)
  — `AboutPanelController.swift` + "Embed About Metadata" build phase.
- [x] 5.2 Verify the panel matches the lockfile/artifact values (scenario check; visual confirmation is part of the 2.3 launch or a second gated launch)
  — Mechanical half verified: built bundle contains MANIFEST.lock (v1.38.0) + RegrepLatest.txt (2026-07-11.md). Visual half rides the 2.3 gated launch.

## 6. Review & ship

- [x] 6.1 Run `/verify`-style end-to-end pass: fresh clone → build → scripts run → scenarios from all three specs hold; fix anything red
  — Done 2026-07-11: pristine clone of the branch → BUILD SUCCEEDED; refresh script no-op correct; vendored sha256 MATCH post-clone; 0 untriaged regrep entries; About resources embedded. Gated launch scenario verified earlier by Calvin ("Both pass").
- [x] 6.2 Ship via git-ship (PR-gated main); PR cites this change and the M0 exit criteria
  — Branch `feat/e1-foundations` pushed (`67ec67b` + task-state commit); PR opened, merge gated on Calvin.
- [ ] 6.3 **[HUMAN GATE — ground rule 3]** Record Calvin's M0 exit verdict (verbatim + timestamp) in `roadmap.md` §1 M0 row or a note under §6, then update `CLAUDE.md` state (E1 done → E2/E3 unblocked)
