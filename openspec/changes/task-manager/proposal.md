# Proposal: task-manager

A Chrome-style **Task Manager** for tabs — see which tabs use the most memory and whether any are
unresponsive.

## What it does

`TaskManagerWindow` — a resizable window listing each tab that has a running WebContent process
(WebKit runs each tab in its own process). Columns:
- **Tab** — favicon + title (the active tab is marked).
- **Memory** — the tab's WebContent process resident memory (MB), read via `ProcessMemory.residentMB`
  (one `/bin/ps` call for all PIDs, the same approach the S1 diagnostic uses; no entitlement needed).
- **Status** — Responsive, or **Not responding** (red): each tab is JS-pinged; if a ping stays
  outstanding > 4s the tab is flagged.
- **PID**.

Rows are sorted by memory (largest first) and refresh every 2s. Select a row (or double-click) to
**Switch to Tab** (focuses it, switching workspace if needed), **Reload** (useful for a hung tab), or
**Close Tab**.

Opened from **File → Task Manager** or the ⌘N command palette ("Task Manager").

## Notes

- Tabs that share a WebContent process (WebKit reuses a process for same-origin tabs) show the same
  PID/memory — same grouping as Chrome's task manager.
- Uses the private `_webProcessIdentifier` KVC to map a web view to its PID (already used by the S1
  diagnostic). App Store caveat: gate private symbols behind a build flag before any MAS submission.

## Impact

New `TaskManagerWindow` + `ProcessMemory`; `AppShell` gains `openTaskManager`, `taskManagerRows`, a
JS-ping responsiveness tracker, and switch/reload/close-by-id; a File-menu item + palette command.
86 XCTests green.
