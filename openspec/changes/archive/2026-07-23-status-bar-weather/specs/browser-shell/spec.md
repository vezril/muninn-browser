# browser-shell

## ADDED Requirements

### Requirement: Weather status bar
Muninn SHALL optionally show a status bar above the web content displaying current weather (temperature,
humidity, US AQI) for a configurable city, using a keyless on-device data source, gated by a setting
(default off).

#### Scenario: show weather
- **WHEN** the status bar is enabled with a valid city
- **THEN** the current temperature, humidity, and US AQI for that city are shown above the web content and
  refreshed periodically

#### Scenario: configure
- **WHEN** the user changes the city or temperature unit
- **THEN** the status bar updates to reflect the new city / unit

#### Scenario: disabled
- **WHEN** the status bar is off
- **THEN** no status bar is shown and no weather is fetched
