# Proposal: e5-injection-frame-registry

## Why

E6's live gate reached a precise blocker: the account app reports **"Proton Pass is missing permissions"** because Muninn injects only `fork.js`, not the general content script `orchestrator.js` that the account app's extension-detection depends on (`research/e6-auth-fork-2026-07-17.md`). That is **E5's work** (FR-9), and the E6 finding **resequences E5 before E6's completion** (ratified by Calvin 2026-07-17). E5 also owns `runtime.getFrameId` (the one genuinely-new API from E1's re-grep, triaged Tier-2/E5).

## What Changes

- **General content-script injection (FR-9), subsuming the minimal `ForkBridgeInjector`:** per the vendored `manifest.json` content_scripts —
  - `orchestrator.js` → isolated `WKContentWorld`, `document_end`, **all frames**, all `http(s)` pages;
  - `webauthn.js` → **MAIN** world, `document_start`, all frames, all `http(s)` pages;
  - `fork.js` → isolated world, `document_end`, `account.proton.me` only (as today).
- **Frame registry (FR-9):** track frames from `WKNavigationDelegate`/`WKFrameInfo` to answer `webNavigation.getFrame`/`getAllFrames` and **`runtime.getFrameId`** (E1 re-grep, Tier-2).
- **Expand the isolated-world `browser.*` surface** to whatever `orchestrator.js` needs to boot without throwing — likely more `runtime`/`tabs`/`i18n`/`scripting` members, and possibly **ports** (`runtime.connect`/`onConnect`), which E2/E3 deferred. Grep `orchestrator.js` to bound this precisely.
- **Verify orchestrator boots clean**, the S2 MAIN-world isolation still holds (the shim API stays out of MAIN world; `webauthn.js` in MAIN world is Proton's own script, not the shim), and the frame registry answers correctly. The E6 gate re-attempt (does "missing permissions" clear?) is **E6's**, not this change — but a cheap early experiment confirms the direction first.

## Capabilities

### New Capabilities
- `content-injection`: injection of `orchestrator.js`/`webauthn.js`/`fork.js` across the correct worlds/frames/pages per the vendored manifest (FR-9), with `orchestrator.js` booting clean.
- `frame-registry`: `webNavigation.getFrame`/`getAllFrames` + `runtime.getFrameId` from `WKFrameInfo`/`WKNavigationDelegate` (FR-9, E1 re-grep).

### Modified Capabilities

_None — `fork-bridge-isolation`/`message-broker` stay as archived; the injector generalization and any port additions are captured under the new capabilities. Superseding the minimal `ForkBridgeInjector` is an implementation refactor, not a spec change._

## Impact

- **Files:** a new `InjectionCoordinator` (subsumes `ForkBridgeInjector`), a `FrameRegistry`, expanded `content-shim.js` (+ possibly the worker/broker port plumbing), new XCTests. `AppShell` uses the coordinator.
- **Unblocks:** E6's completion (the login gate re-attempt) — the goal of the resequence. Also feeds E7 (autofill needs orchestrator running).
- **Risks flagged for design:** orchestrator.js is the large content script — its API needs may pull in deferred ports and more surface; MAIN-world `webauthn.js` must not violate the S2 isolation guarantee (verify it uses no `browser.*`); FR-25 re-grep of `orchestrator.js`'s API usage bounds the shim expansion.
- **Tools:** the `claude-toolkit:webkit` skill / `webkit-developer` agent for `WKContentWorld`/`WKUserScript` all-frames + `WKFrameInfo` frame-identity details.
