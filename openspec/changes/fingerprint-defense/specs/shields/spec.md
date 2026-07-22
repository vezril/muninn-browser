# shields

## ADDED Requirements

### Requirement: Fingerprinting protection (farbling)
Shields SHALL add imperceptible randomized noise to the canvas, WebGL, and Web Audio
fingerprinting surfaces so a page's device fingerprint differs from the real one and across
sessions. It is globally toggleable (default on) and shown in the panel status; `*.proton.me` is
exempt.

#### Scenario: fingerprint differs
- **WHEN** fingerprinting protection is on and a page reads a canvas / WebGL / audio fingerprint
- **THEN** the result carries subtle per-page-load noise (differs from the true fingerprint and
  across loads), while normal rendering/audio is unaffected

#### Scenario: Proton exempt
- **WHEN** the page is on `*.proton.me`
- **THEN** no farbling is applied

#### Scenario: toggle off
- **WHEN** the protection is turned off in Settings → Shields
- **THEN** new page loads are not farbled
