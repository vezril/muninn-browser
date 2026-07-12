# ADR-008 — Canonical Extension Identity Presentation

**Status:** Accepted — Calvin Ference, 2026-07-11 22:55 EDT (architecture.md §10)
**Date:** 2026-07-11
**Source IDs:** FR-13, D4, E6
**Evidence:** `research/spike-a-results.md` (path-derived vs canonical ID finding); `research/2.1-bundle-acquisition.md` (PROTONPASS_EXTENSION_IDS, fallback path is shape-matched)

## Context

Spike A proved that in Chromium contexts the site→extension handshake silently breaks unless the extension carries its canonical production ID (`ghmbeldphafepmbegfdlkpapadhbakde`), because `externally_connectable` targeting is ID-keyed. Research 2.1 refined the picture for Muninn: account.proton.me's *fallback* path (postMessage via fork.js — the path Muninn actually exercises) matches on message **shape**, not extension ID; the ID-keyed broadcast list is only consulted on the `runtime.sendMessage` path that WKWebView never offers. Strictly, Muninn could present any `runtime.id`. But the PRD's approved FR-13 acceptance criterion names the canonical ID literally, Pass's own code may compare `runtime.id` in places the re-grep hasn't flagged yet, and D4's fallback line 3 (Chromium side-load) is hard-keyed to it.

## Decision

**The shim always presents the canonical production identity:** `runtime.id` returns `ghmbeldphafepmbegfdlkpapadhbakde`; `runtime.getURL()` and the custom scheme authority use it (ADR-006); any identity surfaced to `*.proton.me` contexts is this ID. The vendored bundle is never re-keyed or modified.

## Consequences

- FR-13's acceptance criterion is satisfied as literally written — no re-litigation of approved PRD text for a cost of one constant.
- Robustness against the unknown: any ID-comparison inside Pass code (now or in a future release) sees the value it expects; FR-25's re-grep doesn't need to prove the negative ("nothing checks the ID") — cheap insurance against a silent-failure class Spike A demonstrated is real.
- D4 fallback line 3 (CEF side-load) stays exercisable without identity rework; the CRX `"key"`-pinning technique from Spike A remains documented for that path.
- Honesty note recorded: this presentation is *not* load-bearing for the fork.js fallback path itself (shape-matched) — if the S2 spike surfaces an ID-dependent behavior after all, this ADR already covers it; if it never does, the constant costs nothing.
