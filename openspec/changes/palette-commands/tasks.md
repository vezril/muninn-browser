# Tasks: palette-commands

- [x] `CommandPalette`: `Command` struct + `commands` array + `.command(id)` kind; listed ahead of tabs/history
- [x] `AppShell.paletteCommands()` — initial set + Switch-Space per workspace + dev-gated Inspector/View Source
- [x] `AppShell.runPaletteCommand(id)` — dispatch to existing actions; `space:<uuid>` → `switchWorkspace`
- [x] Shortcut hints from `ShortcutStore`; palette closes before opening windows (Settings/Inspector)
- [x] Live-verified (Calvin): commands run; Switch Space filters by name
- [ ] Ship: full suite green; version bump + tag; OpenSpec archive
