# browser-shell

## ADDED Requirements

### Requirement: Task Manager
Muninn SHALL provide a Task Manager window listing each tab with a running WebContent process, showing
its memory and responsiveness, refreshed periodically, with actions to focus, reload, or close a tab.

#### Scenario: list tabs by memory
- **WHEN** the user opens the Task Manager
- **THEN** each tab with a live process is listed with its memory and status, sorted by memory
  (largest first), updating every few seconds

#### Scenario: unresponsive tab flagged
- **WHEN** a tab does not answer a responsiveness ping within a few seconds
- **THEN** it is shown as "Not responding"

#### Scenario: act on a tab
- **WHEN** the user selects a row and chooses Switch to Tab / Reload / Close Tab
- **THEN** that tab is focused / reloaded / closed
