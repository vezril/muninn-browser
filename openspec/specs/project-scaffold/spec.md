# project-scaffold Specification

## Purpose
TBD - created by archiving change e1-foundations. Update Purpose after archive.
## Requirements
### Requirement: Buildable app scaffold on a clean checkout
The repo SHALL contain an Xcode project for a Swift/AppKit app target named Muninn that builds with `xcodebuild` from a fresh clone with no manual setup, and on launch presents a single blank `NSWindow` (the substrate for E6's shell — FR-1's acceptance itself remains with E6).

#### Scenario: Clean-checkout build
- **WHEN** `xcodebuild -scheme Muninn build` runs on a fresh clone
- **THEN** the build succeeds with no manually-installed dependencies beyond Xcode itself

#### Scenario: Launch shows one window
- **WHEN** the built app is launched (after the ground-rule-2 GUI warning is given and Calvin confirms)
- **THEN** exactly one blank window appears and the app quits cleanly

### Requirement: Version-pin display mechanism
The app SHALL provide a debug/About panel (menu-accessible) that displays the vendored Pass extension version, `WebClients` reference, and extraction date from `MANIFEST.lock`, plus the date of the most recent FR-25 re-grep artifact.

#### Scenario: Panel reflects the lockfile
- **WHEN** the About/debug panel is opened
- **THEN** the version, source reference, and dates shown match the current `vendor/pass-extension/MANIFEST.lock` and the newest file in `research/regrep/` (FR-26)

