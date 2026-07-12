# parity-canary Specification

## Purpose
TBD - created by archiving change e1-foundations. Update Purpose after archive.
## Requirements
### Requirement: Repeatable re-grep inventory script
The repo SHALL contain `tools/regrep-inventory.sh` which, on demand, shallow-clones `ProtonMail/WebClients` (main), re-runs Spike B's grep inventory over `applications/pass-extension` and `packages/pass`, and writes a dated markdown artifact to `research/regrep/YYYY-MM-DD.md` containing the namespace/method table and the diff against Spike B's recorded Safari-profile table — completing within NFR-6's practical bound.

#### Scenario: Script produces a dated artifact
- **WHEN** `tools/regrep-inventory.sh` runs with network access
- **THEN** a new `research/regrep/<today>.md` exists containing the permission/namespace table, the diff versus the Spike B baseline, and a placeholder triage section

#### Scenario: Offline failure is loud
- **WHEN** the script runs without network access or the clone fails
- **THEN** it exits non-zero with a clear error and writes no artifact (a silent empty artifact must never satisfy the gate)

### Requirement: Re-grep gate blocks shim code
A dated, human-triaged re-grep artifact SHALL exist before any shim implementation change (E2 onward) begins; every entry in the artifact's diff section SHALL carry a Tier 1/2/3 triage disposition (FR-25).

#### Scenario: Gate satisfied
- **WHEN** the first E2+ change is proposed
- **THEN** `research/regrep/` contains an artifact dated on or after this change's completion whose diff section has zero untriaged entries

#### Scenario: Diff present but untriaged
- **WHEN** the artifact exists but a diff entry lacks a triage disposition
- **THEN** the gate is NOT satisfied and E2+ work does not start (FR-25 acceptance)

