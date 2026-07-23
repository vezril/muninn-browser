# browser-shell

## ADDED Requirements

### Requirement: Tools pane hover-peek
The right Tools pane SHALL reveal on hovering the window's right edge when collapsed (as a floating
overlay that retracts when the cursor leaves), and its show/hide toggle SHALL live inside the pane.

#### Scenario: peek on right-edge hover
- **WHEN** the Tools pane is collapsed and the cursor reaches the right edge
- **THEN** the pane slides in as a floating overlay, and retracts when the cursor leaves it

#### Scenario: pin from the pane
- **WHEN** the user clicks the toggle inside the Tools pane
- **THEN** the pane pins open (or collapses if already open), and the pinned state persists
