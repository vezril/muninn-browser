# ADR-001 — Pass Extension Bundle Acquisition & Vendoring

**Status:** Accepted — Calvin Ference, 2026-07-11 22:55 EDT (architecture.md §10)
**Date:** 2026-07-11
**Source IDs:** AS-8, FR-13, FR-25, FR-26, D2, E1, E6
**Evidence:** `openspec/changes/architecture-and-adrs/research/2.1-bundle-acquisition.md`

## Context

Muninn embeds the production Proton Pass extension bundle (background.js, content scripts, popup/dropdown HTML, WASM crypto) and must refresh it as Proton ships updates (AS-8). The candidate sources differ not just in convenience but in **build target**: Proton ships distinct chrome/firefox/safari builds, and only the Safari target includes `fork.js` — Proton's own content script implementing the postMessage fallback that account.proton.me uses when `chrome.runtime` is absent (as it is in WKWebView). The Chrome CRX, though trivially downloadable with a Google-provided sha256, lacks that bridge entirely and carries Chrome-only baggage. The complete production Safari-target bundle (v1.38.0) sits in plaintext inside the locally-installed *Proton Pass for Safari.app* (`Contents/PlugIns/Safari Extension.appex/Contents/Resources/`) — MAS FairPlay encrypts executables, not resources. The extension source is GPLv3 and per-release git tags exist (`proton-pass@<version>`); `BUILD_TARGET=safari yarn build:extension` produces the same build target without the Xcode/Ruby wrapping steps (byte-level parity with the shipped appex is unverified — that is exactly what the optional S4 spike would quantify).

## Decision

1. **Primary acquisition: extract the Safari-target web bundle from the locally-installed Proton Pass for Safari.app** (plain `cp -R` of the appex `Resources/` web files). Updates ride Mac App Store auto-updates; a refresh script detects version changes by diffing the appex `manifest.json`.
2. **Storage: vendored in-repo** at `vendor/pass-extension/<version>/` with a `MANIFEST.lock` (source, version, sha256, extraction date). Every version bump is a reviewable git diff and triggers the FR-25 re-grep gate. Builds are hermetic.
3. **Escape hatch: pinned-tag source build** (`BUILD_TARGET=safari yarn build:extension` at `proton-pass@<version>`) for debugging, diffing, urgent MAS-lag closure — and the **mandatory** path if Muninn is ever distributed publicly (GPLv3-clean, no store ToS).
4. **CWS `updatecheck` endpoint used as version telemetry only** (Omaha XML gives latest chrome-channel version + hash without downloading) — a cheap "Proton shipped something" signal for NFR-6's turnaround clock. No CRX downloads in the normal workflow.

## Consequences

- Spike B risk 1 is downgraded: Muninn hosts Proton's own `fork.js` per `manifest-safari.json` instead of hand-writing an `onMessageExternal` bridge. Spike **S2** (fork.js fallback fires in WKWebView; no `browserAPI` leak into page world) remains and gates E6.
- Spike **S1** is created: `nativeMessaging` is a *required* permission in `manifest-safari.json` — the FR-12 benign stub must exist before the background host is declared "up" (architecture §8 risk 2).
- Accepted structural lag: the Safari channel trails Chrome by days-to-weeks (observed 1.38.0 vs 1.38.2). Tolerable — the Safari build is already the parity canary (FR-25); the source build closes urgent gaps.
- New standing dependency: Proton Pass for Safari.app must stay installed (free; already present). If Proton ever stops shipping it, fall back to the source build (AS-1 already covers the deeper risk).
- Personal-use extraction is unproblematic (GPLv3 code, own machine). Public distribution must switch to the source build and carry GPLv3 obligations (license + source offer) — recorded as a precondition alongside ADR-003's.
- Spikes S3 (CRX3 unpack) and S4 (source-build parity diff vs appex extraction) are optional, non-gating.
