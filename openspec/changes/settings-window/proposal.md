# Proposal: settings-window

## Why

A real Settings window (Cmd+,) with organized sections — beyond the quick gear menu — including
per-profile configuration, remappable shortcuts, and downloads.

## What Changes

- **`SettingsWindowController`** — a window (centered on first open) with a **top toolbar** nav
  (icons): **General / Profiles / Shortcuts / Advanced**. Toggles are **iOS-style `NSSwitch`**
  sliders; every setting is a row with the description on the **left** and control on the **right**.
- **General:** Warn before quitting (⌘Q confirms) — wired in `AppDelegate.applicationShouldTerminate`.
- **Profiles (master-detail):** left pane lists profiles top→bottom with a **space count** and a
  **＋ / − / ✎** bar at the bottom (add / remove / rename). Right pane = the selected profile's
  settings, now **per-profile:** Search engine, Include search suggestions, Archive tabs
  (auto-archive interval), and **Download location**. Removing a profile moves its workspaces to
  the default and wipes its data.
- **Shortcuts:** click a row's field to **record a new key combo** (Delete resets, Esc cancels);
  the key monitor reads from a persisted `ShortcutStore` (⌃1–9 workspace switch stays fixed).
- **Advanced:** placeholder.
- **Per-profile settings** replace the former globals (search engine / auto-archive / suggestions);
  **downloads** save to the active profile's folder (`WKDownloadDelegate`). Opened via ⌘,, the
  app menu, or the gear menu.

## Impact

`Profile` gains per-profile fields; `AppSettings.warnBeforeQuitting`; new `ShortcutStore` +
`SettingsWindowController`; `InjectionCoordinator` gains download handling; `AppShell` gains the
settings data API, per-profile setting reads, the remappable key monitor, and `openSettings`.
