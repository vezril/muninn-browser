# browser-shell

## ADDED Requirements

### Requirement: Rename a tab
Muninn SHALL let the user give a tab a custom display name that overrides the page title in the
sidebar without changing the tab's content, resettable, and persisted for pinned/favourite tabs.

#### Scenario: rename
- **WHEN** the user right-clicks a tab, chooses Rename…, and enters a name
- **THEN** the sidebar shows that name while the page (and its live title underneath) is unchanged

#### Scenario: reset
- **WHEN** the user chooses Reset Name
- **THEN** the sidebar shows the live page title again

#### Scenario: persists
- **WHEN** a pinned/favourite tab has a custom name and Muninn is relaunched
- **THEN** the custom name is restored

### Requirement: Pinned tabs reopen at their pin
A pinned or favourite tab SHALL reopen at its pinned link (`homeURL`) after being closed/unloaded and
after a relaunch, regardless of where it was last navigated. Regular tabs keep their last location.

#### Scenario: close and reopen
- **WHEN** the user navigates a pinned tab away from its pin, closes it (Cmd+W), then reopens it
- **THEN** it loads the original pinned link, not the last-visited URL
