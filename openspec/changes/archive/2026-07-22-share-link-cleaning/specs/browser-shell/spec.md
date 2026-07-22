# browser-shell

## ADDED Requirements

### Requirement: Share-link tracker stripping
Muninn SHALL remove tracking and attribution parameters from a URL when the user copies or shares it,
without altering the page being viewed, gated by a setting (default on).

#### Scenario: strip platform share tokens
- **WHEN** the user copies or shares a link carrying platform share-attribution parameters (e.g. a
  YouTube link with `si`)
- **THEN** the copied/shared link has those parameters removed

#### Scenario: preserve meaningful parameters
- **WHEN** the shared link also carries meaningful parameters (e.g. a YouTube timestamp `t`, a playlist
  `list`, a Reddit `context`)
- **THEN** those parameters are kept

#### Scenario: setting off
- **WHEN** the strip-trackers-from-shared-links setting is off
- **THEN** links are copied and shared unmodified
