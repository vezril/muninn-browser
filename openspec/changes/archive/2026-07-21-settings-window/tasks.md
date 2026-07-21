# Tasks: settings-window

## 1. Window + General

- [x] 1.1 `SettingsWindowController`: top-toolbar nav (icons) for General/Profiles/Shortcuts/Advanced; centered on first open; NSSwitch toggles; label-left/control-right rows.
- [x] 1.2 General: Warn before quitting (`AppSettings` + `applicationShouldTerminate`).

## 2. Profiles (per-profile settings)

- [x] 2.1 `Profile` per-profile fields (search engine, auto-archive, suggestions, download path); AppShell reads current-profile values; downloads via `WKDownloadDelegate` → profile folder.
- [x] 2.2 Master-detail: list (top-aligned, space counts, +/−/✎) + right form; add/remove(move workspaces + wipe data)/rename.

## 3. Shortcuts

- [x] 3.1 `Shortcut`/`ShortcutAction`/`ShortcutStore` + `ShortcutRecorder`; key monitor reads the store; menus drop duplicate key-equivalents.

## 4. Ship

- [x] 4.1 Full suite green; ship PR-gated; update `CLAUDE.md`; cut version.
