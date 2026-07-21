# Tasks: developer-mode

- [x] `AppSettings.developerMode` (persisted, default off)
- [x] `MuninnWebView : WKWebView` — `willOpenMenu` adds View Page Source + Inspect Element (dev mode only)
- [x] `InjectionCoordinator` creates `MuninnWebView`; sets `developerExtrasEnabled` on the config in dev mode; wires `onViewSource`
- [x] `AppShell.viewSource` (serialized HTML → new tab); `inspectActiveTab`; dev shortcuts ⌥⌘U / ⌥⌘I
- [x] In-app inspector: `_inspector.show` + poll `isVisible` → `detach`; pre-seed `InspectorStartsAttached = NO` at launch
- [x] Settings → Advanced: Developer Mode toggle + `settingsDeveloperMode` (refreshes `isInspectable` on open tabs)
- [x] Live-gated (Calvin): View Source works; Inspect opens a detached, correctly-rendered Web Inspector
- [x] Full suite 61 green; clean build
- [ ] Ship: bump version + tag; OpenSpec archive
