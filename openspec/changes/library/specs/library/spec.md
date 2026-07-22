# library

## ADDED Requirements

### Requirement: Downloads are tracked and shown in the Library
Finished downloads SHALL be recorded (filename, path, source, date, size) and shown in the
Library's Downloads list, newest first. The user SHALL be able to open a download, reveal it in
Finder, and remove it from the list.

#### Scenario: a download appears
- **WHEN** a download finishes
- **THEN** it is recorded and appears in the Library's Downloads list

#### Scenario: open / reveal / remove
- **WHEN** the user double-clicks a download, or uses reveal / remove
- **THEN** the file opens / is revealed in Finder / is removed from the list

### Requirement: Right-click image and link saves are tracked
Because WebKit's native context-menu save bypasses the download delegate, the browser SHALL
provide its own **Save Image** and **Download Linked File** items that route through a tracked
download, and SHALL remove WebKit's native "Download Image".

#### Scenario: Save Image records it
- **WHEN** the user right-clicks an image and chooses "Save Image"
- **THEN** the image downloads and appears in the Library (Downloads and Media)

#### Scenario: native duplicate removed
- **WHEN** the image context menu is shown
- **THEN** WebKit's native "Download Image" is not present (only "Save Image")

### Requirement: The Library is a workspace-tinted left overlay pane
Opening the Library SHALL slide a pane in from the left, over the content, tinted to the current
workspace with rounded corners. It SHALL have Downloads and Media sections, and dismiss on
click-outside, ×, or toggling the button.

#### Scenario: Media grid
- **WHEN** the user selects Media
- **THEN** image/video/audio downloads are shown as a thumbnail grid

#### Scenario: tint follows the space
- **WHEN** the Library is opened in a given workspace
- **THEN** the pane is tinted to that workspace's colour

### Requirement: Library button with hover cue and drop animation
A Library button SHALL sit at the bottom-left of the sidebar beside the workspace switcher, show
a hover cue, and — when a download finishes — play a drop animation into the button.

#### Scenario: hover cue
- **WHEN** the pointer is over the Library button
- **THEN** it highlights (and shows a pointing-hand cursor)

#### Scenario: drop animation
- **WHEN** a download finishes
- **THEN** a file icon drops into the Library button and the button flashes
