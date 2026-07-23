# browser-shell

## MODIFIED Requirements

### Requirement: Weather status bar
Muninn SHALL optionally show a status bar above the web content displaying current weather (temperature,
humidity, US AQI) for a configurable city, using a keyless on-device data source, gated by a setting
(default off). The status bar SHALL be display-only and MUST NOT intercept mouse events intended for
controls beneath it.

#### Scenario: show weather
- **WHEN** the status bar is enabled with a valid city
- **THEN** the current temperature, humidity, and US AQI for that city are shown above the web content and
  refreshed periodically

#### Scenario: does not block controls
- **WHEN** the status bar overlaps a control beneath it (e.g. the Tools-pane toggle)
- **THEN** clicks pass through to that control
