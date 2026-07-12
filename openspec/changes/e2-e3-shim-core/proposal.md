# Proposal: e2-e3-shim-core

## Why

M0 is exited; the walking skeleton's Risk-1 subsystems come next (roadmap E2 + E3, combined per Calvin's direction). The message broker is "the single most important piece" (Spike B) — every Pass flow routes through it — and the background host is where Proton's real `background.js` runs for the first time inside Muninn. E6 (auth-fork login, the first go/no-go gate) is blocked until both exist and the S1 boot spike passes.

## What Changes

- **Message broker (E2 / FR-10, ADR-007):** native hub-and-spoke Swift actor joining `WKScriptMessageHandler` receipts to a routing table; versioned envelope (`brokerV: 1`); Pass payloads treated as opaque bytes — never parsed, logged, or persisted; broker-owned ports surviving ≥5 exchanges; `onMessageExternal` exposed as an inert event surface.
- **Tier-1 API stub layer (E2 / FR-11, FR-12):** native shims + a JS `browser`/`chrome` polyfill (injected into isolated world and extension contexts only — never page MAIN world, per ADR-007) for `alarms`, `storage`, `tabs`, `action`, `windows`, `permissions`, `scripting`, misc `runtime`, `clipboardWrite`, and the benign `nativeMessaging` no-op (skeleton scope per the ratified FR-12 deviation). Unstubbed API access is caught and logged, feeding the audit.
- **Background host (E3 / FR-7, ADR-005):** hidden, always-resident WKWebView with its own `WKWebsiteDataStore`, loading the vendored `background.js` (v1.38.0) via a **minimal** custom-scheme loader; process-level activity assertion; watchdog restart; the FR-7 global-scope audit executed and recorded (S1 spike).
- **Scope boundary:** the scheme loader here serves the background host's own origin only — full FR-8 web-accessible-resource semantics (page-embeddable iframes, S6 initiator identification) remain E4.
- **Test harness:** an XCTest target hosting the broker/stubs/host for execution-grounded exit criteria (round-trips, port survival, S1 boot, crash isolation).

## Capabilities

### New Capabilities
- `message-broker`: runtime messaging between content scripts, extension contexts, and the background host (FR-10).
- `tier1-api-stubs`: the Tier-1 `browser.*` surface + FR-12 stub, sufficient for Pass code to run without throwing (FR-11).
- `background-host`: the always-alive service-worker host with boot audit and resource ceiling (FR-7, NFR-10).

### Modified Capabilities

_None — project-scaffold/parity-canary/pass-bundle-vendor requirements are unchanged (the Xcode project gains a test target and sources, which is implementation, not spec-level behavior)._

## Impact

- **Files:** new `Muninn/Shim/` sources (broker, stubs, host, polyfill JS), `MuninnTests/` test target (pbxproj gains a target), `research/sw-global-scope-audit-<date>.md` (the FR-7/S1 audit artifact).
- **Gates:** FR-25 satisfied (2026-07-11 artifact) — shim code is permitted. S1 must pass before E3 is declared done; the audit log's zero-untriaged bar is re-checked at E8. One gated GUI launch expected (idle RSS/timer measurement, ground rule 2).
- **Unblocks:** E6 (needs broker + host alive); E5's `runtime.getFrameId` stays out of scope here.
- **Ground rule 1 honored structurally:** broker envelope opacity means no code path parses Pass payloads; no login/unlock flows exist yet in this change.
