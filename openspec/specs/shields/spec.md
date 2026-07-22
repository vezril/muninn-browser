# shields Specification

## Purpose
TBD - created by archiving change shields. Update Purpose after archive.
## Requirements
### Requirement: Block ads, trackers, and harden connections by default
The browser SHALL apply, on by default, ad/tracker blocking, HTTPS upgrade, and cross-site cookie
blocking via content rules, globally toggleable in Settings → Shields.

#### Scenario: trackers blocked
- **WHEN** a page requests a known ad/tracker domain as a third party
- **THEN** the request is blocked

#### Scenario: https upgrade
- **WHEN** a page or resource is requested over http and HTTPS upgrade is on
- **THEN** it is upgraded to https

#### Scenario: global toggle
- **WHEN** a protection is turned off in Settings → Shields
- **THEN** it stops applying (after the rule list recompiles) on all tabs

### Requirement: Per-site Shields control
A shield in the address row SHALL open a per-site panel to turn Shields on/off for the site and to
block scripts for the site, showing which protections are active. Per-site state persists.

#### Scenario: shields down for a site
- **WHEN** the user turns Shields off for a site
- **THEN** that site is exempt from all protections (icon shows a slashed shield) and the change
  persists

#### Scenario: block scripts for a site
- **WHEN** the user enables "Block scripts on this site"
- **THEN** JavaScript is disabled for that site's navigations

#### Scenario: status readout (no count)
- **WHEN** the panel is shown
- **THEN** it lists the active protections (active/inactive), without a blocked-request count

### Requirement: Strip tracking query parameters
Shields SHALL remove known tracking query parameters from main-frame navigations before loading,
keeping benign params. It is globally toggleable (default on), honours per-site Shields, and the
panel shows it in the status readout.

#### Scenario: click ID stripped
- **WHEN** the user navigates to a URL containing a tracking param (e.g. `?fbclid=…&id=5`)
- **THEN** the param is removed and the cleaned URL (`?id=5`) is loaded (and stored in history)

#### Scenario: benign params kept
- **WHEN** a URL has only non-tracking params
- **THEN** it is loaded unchanged

#### Scenario: respects per-site Shields and the global toggle
- **WHEN** Shields are down for the site, or the global toggle is off
- **THEN** params are not stripped

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

