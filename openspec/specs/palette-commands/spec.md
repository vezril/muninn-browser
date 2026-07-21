# palette-commands Specification

## Purpose
TBD - created by archiving change palette-commands. Update Purpose after archive.
## Requirements
### Requirement: The command palette runs app commands
The Command Palette SHALL offer app-action commands that run when selected. Commands SHALL be
filterable by typing their title, and SHALL show their keyboard shortcut when one exists. The
search/go line SHALL remain first so Enter on a normal query still searches.

#### Scenario: run a command by name
- **WHEN** the user opens the palette and types "insp" (Developer Mode on)
- **THEN** "Open Inspector" appears and running it opens the inspector

#### Scenario: search is not hijacked
- **WHEN** the user types a normal search query and presses Enter
- **THEN** it searches (the go/search line is selected first), not a command that happens to match

#### Scenario: developer commands are gated
- **WHEN** Developer Mode is off
- **THEN** "Open Inspector" and "View Page Source" do not appear in the palette

### Requirement: Switch Space autocompletes on space names
The palette SHALL offer a "Switch Space" command per workspace (other than the active one),
labelled with the space's icon and name, so typing a space name filters to it.

#### Scenario: switch by typing a space name
- **WHEN** the user types part of a space's name
- **THEN** its "Switch Space: <name>" entry appears and running it switches to that space

