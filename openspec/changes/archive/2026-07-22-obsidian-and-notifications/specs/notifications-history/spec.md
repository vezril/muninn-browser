# notifications-history

## ADDED Requirements

### Requirement: Notifications are recorded and reviewable
Toasts shown by the app SHALL be recorded and shown in a Notifications tool in the Tools sidebar
(newest first, with a relative timestamp), so a missed one can be reviewed. Persisted across
relaunch.

#### Scenario: a missed toast is reviewable
- **WHEN** a toast is shown and dismissed
- **THEN** it appears in the Notifications tool with its message and relative time

#### Scenario: progress toasts are not kept
- **WHEN** a transient progress toast (e.g. "Summarizing page…") is shown
- **THEN** it is not added to the history

### Requirement: Notifications auto-clear on a configurable window and can be cleared manually
The history SHALL auto-prune past a configurable retention window (Settings → General) and SHALL
be manually clearable.

#### Scenario: auto-clear
- **WHEN** a notification is older than the retention window
- **THEN** it is dropped (on launch, periodically, and on new activity)

#### Scenario: manual clear
- **WHEN** the user taps clear in the Notifications tool
- **THEN** the history empties
