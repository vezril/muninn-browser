# Design: e1-foundations

## Context

M0's exit gate (roadmap §1) requires: buildable Xcode project on a fresh checkout, dated + triaged FR-25 re-grep artifact, and the FR-26 display mechanism. ADR-001 (Accepted) pins the bundle path: extract Safari-target from the installed Proton Pass for Safari.app, vendor with lockfile, refresh script. Constraints: solo weekend project; ground rules 1/2/5; architecture.md §4 component boundaries (the scaffold must not preempt E6's shell design, just give it a home).

## Goals / Non-Goals

**Goals:**
- A clean-checkout `xcodebuild` succeeds; launching the app shows one blank window (manually verified once, with the GUI warning).
- `tools/regrep-inventory.sh` produces `research/regrep/YYYY-MM-DD.md` (namespace/method table diffed against Spike B's recorded Safari profile) in ≤5 min; first run's diff is triaged in-file.
- `vendor/pass-extension/<version>/` holds the extracted Safari-target bundle; `MANIFEST.lock` records source/version/sha256/date; `tools/refresh-pass-bundle.sh` re-extracts and diffs on demand.
- Debug/About panel shows the values from `MANIFEST.lock` + latest re-grep date (FR-26 mechanism).

**Non-Goals:**
- No WKWebView, no tabs, no navigation (E6); no shim code of any kind (E2/E3 — and forbidden until the re-grep artifact exists).
- No spike execution (S1/S2/S5/S6 belong to E3/E6/E8/E4 respectively).
- No CI, no signing/notarization (ADR-003: unsigned personal builds), no SwiftPM dependencies.

## Decisions

1. **Project generation: plain Xcode app template, checked in as-is** (no XcodeGen/Tuist) — zero extra tooling for a solo repo; project-file churn is tolerable at this scale.
2. **Swift 6 / AppKit lifecycle (`NSApplicationDelegate`), no storyboards** (programmatic window) — matches architecture §4's AppKit-owned Shell and avoids Interface Builder merge pain.
3. **Bundle target layout:** `Muninn/` (app sources), `tools/` (repo scripts), `vendor/` (Pass bundle), `research/regrep/` (dated artifacts) — mirrors what prd/roadmap/architecture already reference.
4. **Re-grep script is bash + ripgrep over a shallow clone** into a temp dir (no submodule — WebClients is multi-GB with history; shallow clone of `main` is minutes). The script prints the permission/namespace table and writes the markdown artifact; triage notes are added by hand below the generated table.
5. **The vendored bundle is committed** (GPLv3 permits; repo already public) — hermetic builds, reviewable version-bump diffs, bisectable regressions (ADR-001).
6. **About/debug panel is a menu item → plain window reading `MANIFEST.lock` + `research/regrep/` at runtime from bundled copies** — the simplest FR-26 mechanism; no settings framework.

## Risks / Trade-offs

- [Proton Pass for Safari.app missing/updated mid-work] → refresh script fails loudly with instructions; MAS install is a one-time manual action (free, ground rule 5 notes it).
- [Re-grep diff shows new API surface vs Spike B] → that is the gate *working*: triage in-artifact (Tier 1/2/3 disposition) before E2+ proceeds; a large diff may bounce scope back to the architecture change.
- [Committed vendor bundle bloats repo] → the web bundle subset is ~10–20 MB/version; keep only the current version + lockfile history, prune superseded versions on bump.
- [Xcode project file merge conflicts later] → single developer; accepted.

## Migration Plan

Not applicable — additive change; rollback = revert the PR.

## Open Questions

- None blocking. (Bundle version at extraction time is whatever the MAS app currently holds — recorded in the lockfile, not chosen.)
