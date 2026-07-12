# Proposal: architecture-and-adrs

## Why

The SDLC pipeline blocks implementation until the architecture exists as a file: `roadmap.md` E1–E12 all assume an approved HLD, and four questions are explicitly deferred "to the architecture phase" (Pass bundle acquisition, egress-audit tooling ownership, App Store sandbox investigation, FR-24 test-harness feasibility). Producing the architecture + ADRs now is the last Solutioning prerequisite before any epic can be story-planned or coded.

## What Changes

- Add `architecture.md` — the system HLD: driving characteristics derived from the PRD's NFRs, chosen architecture style with trade-offs, component boundaries for the shell and the four Tier-2 shim subsystems (background host, scheme handler, injection/frame registry, message broker), C4 context/container diagrams, and risk analysis.
- Add `adr/` — Architecture Decision Records (Nygard format) for each load-bearing decision, including the four deferred architecture-phase questions from `roadmap.md` §5 and PRD §11/§12:
  - Pass extension bundle acquisition/vendoring mechanism (AS-8)
  - Egress-audit tooling: throwaway proxy setup vs. reusable harness (NFR-5 gap)
  - Distribution: sandbox-vs-shim investigation backing OQ-5's direct-download resolution
  - FR-24 Apple Pay injection-suspension test approach (fault injection now, live merchant later)
  - Plus core technical choices: background host substrate (hidden WKWebView vs. JSContext), custom scheme design, message-broker contract, canonical-ID presentation strategy
- No production code changes — this is a documentation/decision change. Implementation of the architecture happens in the per-epic changes that follow (E1 first).

## Capabilities

### New Capabilities
- `architecture-record`: the repo carries a reviewed architecture (HLD) and ADR set that per-epic changes can cite — every locked decision and deferred architecture-phase question has a recorded, traceable resolution, gated by Calvin's approval (ground rule 3).

### Modified Capabilities

_None — `openspec/specs/` is empty; this is the project's first change._

## Impact

- **Files added:** `architecture.md`, `adr/ADR-001…N.md` (repo root level, alongside `prd.md`/`roadmap.md`).
- **Pipeline state:** unblocks Solutioning → per-epic changes (E1 next). `CLAUDE.md` artifact-state section updates on completion.
- **Human gates:** two — Calvin's PRD/roadmap approval (`prd.md` §13, `roadmap.md` §6) must be recorded before this change's outputs are treated as approved; the architecture itself then gets its own verbatim verdict (ground rule 3). Drafting may proceed ahead of the first gate; nothing downstream may.
- **No dependencies added; no code, build, or CI impact.**
