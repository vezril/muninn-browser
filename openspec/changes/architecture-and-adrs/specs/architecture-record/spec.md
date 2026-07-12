# architecture-record

## ADDED Requirements

### Requirement: Architecture document covers the mandated HLD content
The repo SHALL contain `architecture.md` covering, for M0–M2 scope: driving architecture characteristics derived from the PRD's NFRs (each citing its NFR ID), the chosen architecture style with trade-offs, component boundaries for the shell and the four Tier-2 shim subsystems (background service-worker host, custom-scheme resource handler, content-world injection + frame registry, message broker), C4 context and container diagrams, and a risk analysis keyed to Spike B's three ordered risks.

#### Scenario: HLD sections present and traceable
- **WHEN** `architecture.md` is reviewed against this requirement's content list
- **THEN** every listed section exists, every driving characteristic cites at least one PRD NFR ID, and every component named in the C4 container diagram maps to at least one PRD FR

#### Scenario: Scope boundary respected
- **WHEN** `architecture.md` is searched for Sync-layer or M3-only design content
- **THEN** sync appears only as an explicitly-labeled future extension point (per OQ-3), with no protocol or hosting design

### Requirement: ADR set covers deferred questions and core technical choices
The repo SHALL contain an `adr/` directory with one Nygard-format ADR (Status, Context, Decision, Consequences) per load-bearing decision, including at minimum: Pass extension bundle acquisition (AS-8), egress-audit tooling ownership (NFR-5 gap), distribution sandbox investigation (OQ-5), FR-24 Apple Pay test approach, background-host substrate, custom URL scheme design, message-broker contract, and canonical extension ID presentation (FR-13).

#### Scenario: Every mandated topic has an ADR
- **WHEN** the `adr/` directory is checked against the eight mandated topics
- **THEN** each topic resolves to exactly one ADR file with all four Nygard sections non-empty

#### Scenario: Unresolvable decision recorded honestly
- **WHEN** a mandated topic cannot be decided at desk level
- **THEN** its ADR exists with status `Proposed (needs spike)` and names the spike required, rather than the topic being silently omitted

### Requirement: Architecture record is consistent with locked decisions and the PRD
Every ADR and `architecture.md` SHALL cite the PRD/roadmap/decisions IDs it depends on (FR/NFR/AS/OQ/D/E), SHALL NOT contradict locked decisions D1–D4, and SHALL NOT encode Proton Pass API details tighter than Spike B's Safari-profile table (re-validation belongs to E1's FR-25 gate).

#### Scenario: Mechanical traceability check passes
- **WHEN** a script extracts all FR/NFR/AS/OQ/D/E references from `architecture.md` and `adr/*.md`
- **THEN** every reference resolves to an ID defined in `prd.md`, `roadmap.md`, or `decisions.md`, and at least one reference exists per ADR

#### Scenario: Locked-decision conflict is rejected
- **WHEN** review finds an ADR proposing an engine, name, or language-split choice differing from D1–D4
- **THEN** the change fails review and the ADR is corrected before the human gate

### Requirement: Architecture approval is human-gated
The architecture record SHALL NOT be treated as approved until Calvin's verbatim verdict and timestamp are recorded in `architecture.md`; all ADR statuses SHALL remain `Proposed` until that verdict, and per-epic implementation changes SHALL NOT begin before both the PRD gate (`prd.md` §13) and the architecture gate are recorded.

#### Scenario: Gate blocks downstream work
- **WHEN** the architecture record exists but `architecture.md` contains no recorded verdict
- **THEN** all ADRs carry status `Proposed` (or `Proposed (needs spike)`) and no per-epic implementation change is created

#### Scenario: Approval flips statuses
- **WHEN** Calvin's approval verdict is recorded verbatim with a timestamp in `architecture.md`
- **THEN** accepted ADRs are updated to status `Accepted` in the same commit
