# Proposal: fingerprint-defense

## Why

From Brave's grab-bag #2 (https://brave.com/privacy-updates/8-grab-bag-2/): fingerprinting
mitigations (canvas/WebGL/etc.). Brave "farbles" high-entropy APIs. WKWebView can't match a
native engine, but a MAIN-world script can neutralise the classic canvas/WebGL/audio fingerprints
— a real addition to the Shields suite.

## What

- **`FingerprintDefense.script`** — MAIN-world, document-start, all frames: a per-page-load seeded
  PRNG adds imperceptible noise to canvas readback (`getImageData`/`toDataURL`/`toBlob`), spoofs
  WebGL `UNMASKED_VENDOR/RENDERER_WEBGL` to generic values, and noises Web Audio
  (`getChannelData`/`getFloatFrequencyData`). So the device fingerprint differs from the real one
  and across sessions/sites.
- Injected by `InjectionCoordinator` on content tabs when `ShieldsManager.fingerprintProtection`
  is on (default on). **`*.proton.me` is exempt** (the shim/auth-fork path stays pristine).
- **Settings → Shields** toggle + a panel status row.

## Scope / honesty

- Applied at **tab creation** (toggling affects new tabs; reopen to change) and currently **global**
  (not gated by the per-site Shields master yet) — both future refinements.
- Covers canvas/WebGL/audio — not every surface a native engine randomizes (JS reach only).

## Impact

New `FingerprintDefense`; `fingerprintProtection` flag on `ShieldsManager`; one injected user
script; Settings + panel gain a row. No content-rule recompile.
