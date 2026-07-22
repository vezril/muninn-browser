# Tasks: task-manager

- [x] `ProcessMemory.residentMB(pids:)` — batched `/bin/ps` RSS lookup
- [x] `TaskManagerWindow` — NSTableView (Tab/Memory/Status/PID), 2s refresh, sort by memory, actions
- [x] `AppShell.taskManagerRows()` — per-tab PID (`_webProcessIdentifier`) + memory + responsiveness
- [x] JS-ping responsiveness tracker (outstanding > 4s → Not responding)
- [x] Switch/Reload/Close by tab id (switch crosses workspaces)
- [x] Filter on live process (not the lazy isLoaded flag) so landing/restored tabs appear
- [x] File → Task Manager menu item + command-palette entry
- [x] 86 XCTests green
- [x] Version bump → v0.25.0
