# Proposal: e1-foundations

## Why

Every downstream epic (E2–E12) is blocked on E1: no Xcode project exists, FR-25's re-grep gate must clear before a single line of shim code is written, and per ADR-001 the vendored Pass bundle is a hard prerequisite for E6/E7/E8's acceptance criteria. This change is roadmap E1 — the M0 exit.

## What Changes

- Create the Muninn Xcode project (Swift/AppKit app target) that builds and launches a blank `NSWindow` on a clean checkout — the substrate for E6's real shell, not FR-1's acceptance itself.
- Add the debug/About panel **mechanism** that will display the validated Pass extension version + `WebClients` commit (FR-26 — populated for real once FR-25 runs; the display plumbing ships here).
- Execute the **FR-25 parity-canary re-grep gate**: re-run Spike B's grep inventory against `ProtonMail/WebClients` main, diff against the recorded Safari-profile table, record a dated triage artifact. Repeatable via a checked-in script (NFR-6's 1-business-day turnaround).
- **Vendor the Pass bundle per ADR-001**: extract the Safari-target web bundle from the locally-installed Proton Pass for Safari.app into `vendor/pass-extension/<version>/` with a `MANIFEST.lock` (source, version, sha256, date), plus the `tools/refresh-pass-bundle.sh` refresh script.
- Repo hygiene to support the above: `.gitignore` (Xcode noise, `*.pcapng`), basic project layout.

## Capabilities

### New Capabilities
- `project-scaffold`: the buildable/launchable AppKit app shell and the FR-26 version-pin display mechanism.
- `parity-canary`: the repeatable FR-25 re-grep gate — script, dated artifact, triage record (NFR-6).
- `pass-bundle-vendor`: the vendored, hash-locked Safari-target Pass bundle and its refresh workflow (AS-8, ADR-001).

### Modified Capabilities

_None — `architecture-record` is unaffected; this change implements decisions it records._

## Impact

- **Files added:** Xcode project (`Muninn.xcodeproj`, `Muninn/` sources), `tools/regrep-inventory.sh` + `research/regrep/<date>.md` artifact, `vendor/pass-extension/<version>/` + `MANIFEST.lock`, `tools/refresh-pass-bundle.sh`, `.gitignore`.
- **Gates honored:** FR-25 artifact must exist and be triaged **before any E2+ shim code**; ground rule 2 (warn before GUI launch) applies to the build-verification step; ground rule 5 (no Homebrew installs without asking) applies if tooling is missing.
- **Unblocks:** E2/E3 immediately; E6/E7/E8 depend on the vendored bundle from this change.
- **No Proton credentials touched anywhere in this change** (ground rule 1) — the bundle extraction is a file copy; the re-grep is a public-repo clone.
