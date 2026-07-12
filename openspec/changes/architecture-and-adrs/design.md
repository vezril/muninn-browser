# Design: architecture-and-adrs

## Context

Planning is drafted (`prd.md`, `roadmap.md`, both awaiting Calvin's gate). Nothing in the repo yet records *how* the system hangs together: the four Tier-2 shim subsystems are named but not designed, and four questions were explicitly punted to this phase (Pass bundle acquisition — AS-8; egress-audit tooling ownership — roadmap §5; sandbox-vs-shim investigation — OQ-5; FR-24 test approach). Constraints are fixed: D1–D4 are locked, the shim spec is Proton's Safari build profile (Spike B), and this is a solo weekend project — the HLD must be decision-dense, not ceremony-dense.

## Goals / Non-Goals

**Goals:**
- One `architecture.md` (HLD) covering M0–M2 scope: driving characteristics derived from the PRD's NFRs, architecture style, component boundaries (shell + background host + scheme handler + injection/frame registry + message broker), C4 context/container diagrams (Mermaid), risk analysis keyed to Spike B's three risks.
- An ADR per load-bearing decision (Nygard format: Status/Context/Decision/Consequences), including the four deferred questions and the core technical choices (background-host substrate, custom-scheme design, broker message contract, canonical-ID presentation).
- Every ADR traceable to PRD FR/NFR/AS/OQ IDs and consistent with `decisions.md` D1–D4.

**Non-Goals:**
- No Sync-horizon architecture (OQ-3 defers it to its own PRD cycle).
- No M3/P2 design beyond noting extension points (passkeys, biometric gates).
- No code, no Xcode project — that is E1, a separate change.
- No re-litigation of D1–D4.

## Decisions

1. **Artifacts live at repo root (`architecture.md`, `adr/`)**, alongside `prd.md`/`roadmap.md`, not under `openspec/` — they are living repo docs (the SDLC convention: system-level HLD/ADRs stay repo docs; the change only tracks producing them). Alternative (docs/ subdir) rejected: the existing artifact set is flat at root.
2. **Maker-checker production**: solution-architect agent drafts; a separate reviewer agent critiques against PRD/spikes/decisions; mechanical checks (ID references resolve, every mandated ADR topic present) run before the human gate — same discipline that caught 6 blocking PRD defects.
3. **ADRs are numbered ADR-001… in decision order, one file each**, status starts `Proposed`, flips to `Accepted` only with Calvin's recorded verdict. Alternative (single ADR log file) rejected: per-epic changes need stable per-decision links.
4. **Investigations stay desk-level.** The sandbox investigation (OQ-5) and bundle-acquisition ADR are decided on documented evidence (Apple docs, WebClients build outputs), not new spikes — if desk research proves insufficient, the ADR records `Proposed (needs spike)` and the spike becomes its own task rather than blocking the whole change.
5. **C4 diagrams in Mermaid inside `architecture.md`** — renderable on GitHub, no tooling dependency. Level 1 (context) + Level 2 (container) only; component-level detail lives in the per-epic changes.

## Risks / Trade-offs

- [Architecture drafted before Calvin's PRD verdict lands] → drafting may proceed (it inherits the pending gate), but nothing downstream (E1 stories/code) starts until both gates are recorded; if his PRD verdict changes an FR, the HLD gets a bounded revision pass before its own gate.
- [Desk-level sandbox/bundle research proves wrong later] → ADR status field records confidence; a wrong `Accepted` ADR is superseded by a new ADR (Nygard supersession), not edited in place — history stays honest.
- [Solo-project gold-plating: too many ADRs] → cap at the enumerated topics (4 deferred questions + 4–5 core choices); anything else is a line in `architecture.md`, not an ADR.
- [Spike B inventory drift before design lands] → the HLD cites Spike B as of Pass v1.38.2 and explicitly defers re-validation to E1's FR-25 gate; the architecture must not encode API details tighter than the Safari-profile table.

## Migration Plan

Not applicable — documentation-only change. Rollback = revert the commit; no state to migrate.

## Open Questions

- Does Calvin want the sandbox investigation (OQ-5) to *conclude* in this change, or is `Proposed (needs spike)` an acceptable ADR outcome? (Default per Decision 4: desk-level is acceptable.)
- Apple Developer Program enrollment status (AS-7) — affects the distribution ADR's consequences section but not its decision.
