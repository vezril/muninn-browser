# developer-mode

## ADDED Requirements

### Requirement: Developer Mode gates the developer affordances
A **Developer Mode** setting (Settings → Advanced) SHALL default to off. Only while it is on
do the developer right-click items and shortcuts appear, and only then is web content made
inspectable.

#### Scenario: off by default
- **WHEN** the app is first run
- **THEN** Developer Mode is off, the right-click menu is unchanged, and the private inspector
  path is never invoked

#### Scenario: toggling on
- **WHEN** the user enables Developer Mode
- **THEN** right-click gains View Page Source and Inspect Element, ⌥⌘U / ⌥⌘I work, and web views
  become inspectable

### Requirement: View Page Source
In Developer Mode, the user SHALL be able to open the current page's HTML source.

#### Scenario: from the menu / shortcut
- **WHEN** the user picks "View Page Source" (or presses ⌥⌘U)
- **THEN** the page's serialized HTML opens in a new tab

### Requirement: Inspect opens the in-app Web Inspector, detached
In Developer Mode, "Inspect Element" (or ⌥⌘I) SHALL open the real WebKit Web Inspector in-app,
as a detached window that renders correctly.

#### Scenario: inspector opens and renders
- **WHEN** the user picks "Inspect Element" (or presses ⌥⌘I)
- **THEN** the Web Inspector opens as its own window with working panels (elements / console /
  network / sources) — not docked, not blank, not flickering

#### Scenario: detached is remembered
- **WHEN** the inspector has been opened once
- **THEN** subsequent opens (including from WebKit's own menu item) come up detached

#### Scenario: fails closed
- **WHEN** the private inspector API is unavailable
- **THEN** Inspect is a no-op (no crash), and the public inspectable + Safari Develop-menu route
  still works
