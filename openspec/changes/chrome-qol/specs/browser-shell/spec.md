# browser-shell

## ADDED Requirements

### Requirement: Top-bar tool cluster
The browser chrome SHALL present the shield, settings, and extension-action buttons as a cluster on
the top bar, to the right of the nav cluster, separated by a vertical divider. The address field
SHALL occupy the full sidebar width below the top bar and SHALL be single-line.

#### Scenario: clusters are separated
- **WHEN** the sidebar is shown
- **THEN** the nav buttons and the shield/settings/extension buttons appear as two clusters with a
  vertical divider between them, without overlapping

#### Scenario: single-line address field
- **WHEN** a long URL is shown or typed
- **THEN** the address field stays one line (truncating/scrolling), never wrapping

### Requirement: Share the current page
The chrome SHALL provide a share control in the address area that opens the macOS share sheet for the
current page URL.

#### Scenario: share
- **WHEN** the user clicks the share button
- **THEN** the standard macOS share sheet opens with the current page URL

### Requirement: Resizable side panes
The left sidebar and the right Tools sidebar SHALL be resizable by dragging their inner edge, within
clamped bounds, and the chosen widths SHALL persist across launches.

#### Scenario: resize and persist
- **WHEN** the user drags a pane's inner edge
- **THEN** the pane resizes (clamped) and the width is restored on the next launch

### Requirement: Mouse navigation buttons
The browser SHALL support mouse extra-buttons: side buttons navigate back/forward on the active tab,
and middle-click opens a new tab that preserves the current tab.

#### Scenario: side buttons
- **WHEN** the user presses the mouse back/forward side button
- **THEN** the active tab navigates back/forward

#### Scenario: middle-click a link
- **WHEN** the user middle-clicks a link
- **THEN** the link opens in a background tab and the current tab stays put

#### Scenario: middle-click a nav button
- **WHEN** the user middle-clicks back/forward/reload
- **THEN** that target opens in a background tab, leaving the current tab unchanged

### Requirement: Chrome hover feedback
All chrome icon buttons SHALL show a hover cue (highlight + pointing-hand cursor), and buttons with a
state tint (e.g. shields-down, tools-open) SHALL keep that tint after the cursor leaves.

#### Scenario: hover
- **WHEN** the cursor is over a chrome icon button
- **THEN** it shows a rounded highlight and the pointing-hand cursor
