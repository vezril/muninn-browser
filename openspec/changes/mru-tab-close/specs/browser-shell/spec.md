# browser-shell

## ADDED Requirements

### Requirement: Most-recently-used tab on close
When the active tab is closed, Muninn SHALL activate the most-recently-used remaining tab in the
workspace, rather than the first tab in the list.

#### Scenario: close returns to the previous tab
- **WHEN** the user closes the active tab
- **THEN** the tab they were on just before it becomes active
