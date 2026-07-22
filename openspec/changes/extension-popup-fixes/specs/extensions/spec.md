# extensions

## MODIFIED Requirements

### Requirement: Extension action toolbar and popups
Muninn SHALL show a toolbar button for each loaded extension's action on the address row;
activating it presents the extension's popup (if it declares one) or fires the action's click
event. The popup SHALL be dismissable (click-outside / Esc) and SHALL render even when the popup
sizes itself to the viewport.

#### Scenario: open a popup
- **WHEN** the user clicks the action button of an extension that declares a default popup
- **THEN** the popup is presented anchored to the button and can be dismissed by clicking outside or Esc

#### Scenario: self-sizing popup still renders
- **WHEN** a popup sizes itself to the viewport (which WebKit initially reports as ~1×1)
- **THEN** the browser gives it a default size so it renders instead of collapsing to blank

#### Scenario: popup-less action
- **WHEN** the user clicks the action button of an extension with no popup
- **THEN** the extension's action click event fires
