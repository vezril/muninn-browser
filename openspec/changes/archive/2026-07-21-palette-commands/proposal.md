# Proposal: palette-commands

## Why

The Command Palette (⌘N) could open URLs, search, switch to an open tab, or jump to history —
but not **do** anything. Arc's command bar runs app actions ("Open Inspector", "Clean Up",
"Switch Space"). This adds an action layer as the foundation for a growing command set (more
land as new tools are built).

## What

A `command` item kind in the palette. `AppShell` supplies a list of app commands; typing filters
by title and Enter runs the action. Each shows its (remappable) keyboard shortcut on the right.
The search/go line stays first so Enter on a normal query still searches — commands are reached
by filtering or arrowing down.

Initial set: **Pin / Unpin / Favourite / Unfavourite Current Tab**, **Clean Up** (clear unpinned),
**Toggle Sidebar**, **Toggle Tools Sidebar**, **Open Last Tab** (reopen last closed), **Reload**,
**Copy URL**, **Open Settings**, and **Switch Space** — expanded to one entry per workspace
(icon + name) so typing a space name autocompletes to it. Developer Mode adds **Open Inspector**
and **View Page Source**.

## Impact

`CommandPalette`: new `Command` struct + `commands` array + `.command(id)` kind, listed ahead of
tabs/history. `AppShell`: `paletteCommands()` (dynamic — Switch-Space per workspace, dev entries
gated) + `runPaletteCommand(id)` dispatching to existing actions. No new behaviors — commands
reuse existing methods (`setKind`, `clearUnpinnedTabs`, `switchWorkspace`, `inspectActiveTab`, …).
Growing the set later = one entry + one dispatch case. No shim/persistence changes.
