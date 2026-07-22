# shields

## ADDED Requirements

### Requirement: Cosmetic ad hiding
When Shields "Block ads & trackers" is on, Muninn SHALL cosmetically hide common ad-slot containers so
that blocked ads leave no empty space (e.g. a blank sticky footer). `*.proton.me` is exempt.

#### Scenario: empty ad slot hidden
- **WHEN** an ad network is blocked and the page leaves an empty ad-slot container (e.g. `.adthrive-ad`)
- **THEN** the container is hidden and no blank bar is shown
