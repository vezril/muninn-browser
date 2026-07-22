# extensions

## ADDED Requirements

### Requirement: Install from the Chrome Web Store
Muninn SHALL let the user install an extension by pasting a Chrome Web Store URL (or a bare
32-character extension id): it downloads the CRX from Google's update endpoint, strips the CRX
header to the embedded ZIP, and loads it through the normal unpack path.

#### Scenario: install by store URL
- **WHEN** the user enters a Chrome Web Store link and presses Install
- **THEN** the extension id is extracted, the CRX downloaded and unpacked, and the extension loaded
  and listed

#### Scenario: install by id
- **WHEN** the user enters a bare 32-character extension id
- **THEN** it installs the same way

#### Scenario: invalid input
- **WHEN** the input contains no valid extension id
- **THEN** installation fails with an explanatory message and nothing is added

## MODIFIED Requirements

### Requirement: Extension action toolbar and popups
Muninn SHALL show a toolbar button for each loaded extension's action on the address row (so a
variable number of icons never clips off a narrow sidebar); activating it presents the extension's
popup (if it declares one) or fires the action's click event.

#### Scenario: open a popup
- **WHEN** the user clicks the action button of an extension that declares a default popup
- **THEN** the popup is presented anchored to the button

#### Scenario: popup-less action
- **WHEN** the user clicks the action button of an extension with no popup
- **THEN** the extension's action click event fires

#### Scenario: icons stay clickable on a narrow sidebar
- **WHEN** the sidebar is at its minimum width and an extension is enabled
- **THEN** the extension's action icon is fully visible on the address row and clickable
