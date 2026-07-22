# shields

## ADDED Requirements

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
