# Proposal: status-bar-weather

A compact **status bar** above the web content — starting with **weather** (temperature, humidity, US
AQI) for a configurable city. Toggleable, with its own Settings section, and built to grow.

## What it does

When enabled, the previously-empty 34px title-bar strip above the web card shows a row of icon+text
chips: **📍 City · 🌡 temp · 💧 humidity · 🌫 AQI** — the AQI value colour-coded by US band (green →
maroon). Refreshes on launch + every 20 minutes; reuses wasted space, so it costs no browsing area.

## Data source

**Open-Meteo** — free, **no API key, no account**, fetched natively over `URLSession` (privacy-aligned).
Geocodes the city → coordinates (cached per city), then pulls current weather + US AQI. Three endpoints,
verified live; parsing is pure + unit-tested.

## Configuration

A new **Settings → Status Bar** section: "Show status bar" toggle (default off), **City** field (default
**Montreal**), and a **°C/°F** toggle. Changes apply live via `AppShell.applyStatusBar()`.

## Extensibility

Named "Status Bar" (not "Weather") and built as a chip row, so future statuses are just more chips + more
settings — no restructuring.

## Impact

New `Muninn/Status/` — `WeatherService` (Open-Meteo fetch + pure parsers), `StatusBarSettings`,
`StatusBarView` (chip row + AQI colours). `AppShell` gains the status bar in the top strip + weather
refresh loop (`applyStatusBar`/`refreshWeather`); `SettingsWindowController` gains the Status Bar section.
121 XCTests green (+5 `WeatherServiceTests`); live-gated (endpoints verified: Montreal 14.5°C / 75% / AQI 42).
