# pass-bundle-vendor Specification

## Purpose
TBD - created by archiving change e1-foundations. Update Purpose after archive.
## Requirements
### Requirement: Vendored Safari-target bundle with lockfile
The repo SHALL contain the Safari-target Pass extension web bundle, extracted from the locally-installed Proton Pass for Safari.app per ADR-001, at `vendor/pass-extension/<version>/`, together with `vendor/pass-extension/MANIFEST.lock` recording: source (`safari-appex`), extension version, `WebClients` reference where known, per-bundle sha256, and extraction date. The vendored tree MUST include `manifest.json`, `background.js`, the content scripts (`orchestrator.js`, `fork.js`, `webauthn.js`), the UI pages (`popup.html`, `dropdown.html`, `notification.html`), and all `*.wasm` payloads; Proton-native `.bundle` payloads are excluded.

#### Scenario: Bundle integrity verifiable
- **WHEN** the lockfile's sha256 is recomputed over the vendored tree
- **THEN** it matches, and `manifest.json`'s version equals the lockfile's version (AS-8)

#### Scenario: fork.js present
- **WHEN** the vendored manifest's content_scripts are inspected
- **THEN** `fork.js` is declared for the account.proton.me match pattern — the artifact that makes FR-13's reframed flow possible (ADR-001)

### Requirement: Refresh workflow
The repo SHALL contain `tools/refresh-pass-bundle.sh` which detects a version change in the installed Proton Pass for Safari.app, re-extracts the web bundle, writes an updated lockfile, and prints a diff summary of `manifest.json` and entry points; it SHALL remind the operator that a version bump triggers the FR-25 re-grep gate before the new bundle is used by shim code.

#### Scenario: No-op on same version
- **WHEN** the installed app's extension version equals the lockfile version
- **THEN** the script reports "up to date" and changes nothing

#### Scenario: Version bump flow
- **WHEN** the installed app holds a newer extension version
- **THEN** the script extracts to a new `vendor/pass-extension/<new-version>/`, updates the lockfile, prints the manifest diff, and prints the FR-25 re-grep reminder (NFR-6)

#### Scenario: Source app missing
- **WHEN** Proton Pass for Safari.app is not installed
- **THEN** the script exits non-zero with instructions (MAS install is a manual human action; the script never attempts installation)

