# shields

## ADDED Requirements

### Requirement: Bounce-tracking protection (debouncing)
Shields SHALL detect navigations to known bounce-trackers that carry the destination in a query
param and navigate straight to the destination, skipping the tracker. Globally toggleable
(default on), per-site honoured, shown in the panel status.

#### Scenario: skip the tracker
- **WHEN** the user navigates to a known bounce-tracker URL carrying the destination (e.g.
  `l.facebook.com/l.php?u=<dest>`)
- **THEN** the browser loads `<dest>` directly (and then query-strips it)

#### Scenario: non-trackers unaffected
- **WHEN** a URL is not a known bounce-tracker, or carries no destination param
- **THEN** it is loaded unchanged

## MODIFIED Requirements

### Requirement: Fingerprinting protection (farbling)
Shields SHALL add noise to the canvas, WebGL, Web Audio, `measureText`, and `hardwareConcurrency`
surfaces and reduce language entropy (`navigator.languages` → primary), seeded per **session and
per-site** (`hash(sessionToken + eTLD+1)`) so values are consistent within a session for a site but
differ across sites and sessions. Global toggle (default on); `*.proton.me` exempt.

#### Scenario: consistent within a session, different across
- **WHEN** a site reads a fingerprintable surface twice in one session
- **THEN** it gets the same farbled value; a different site (or a new session) gets a different one

#### Scenario: Proton exempt
- **WHEN** the page is on `*.proton.me`
- **THEN** no farbling is applied
