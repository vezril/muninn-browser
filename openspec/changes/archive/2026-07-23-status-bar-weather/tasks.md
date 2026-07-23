# Tasks: status-bar-weather

- [x] `WeatherService` — Open-Meteo geocode + weather + US AQI (async, cached coords); pure parsers.
- [x] `StatusBarSettings` — enabled / city (default Montreal) / fahrenheit.
- [x] `StatusBarView` — icon+text chips (city/temp/humidity/AQI), US-AQI band colours; loading/unavailable.
- [x] `AppShell` — status bar in the top strip (centred over the web card, reuses the 34px title strip);
      `applyStatusBar` + `refreshWeather` (launch + 20-min timer); started in `present()`.
- [x] Settings → Status Bar section (toggle + city field + °C/°F), applies live.
- [x] `WeatherServiceTests` (5) — geocode/weather/AQI parsing + AQI colour bands. Suite green (121).
- [x] Verified Open-Meteo endpoints live; live-gated in-app.
