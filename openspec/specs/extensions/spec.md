# extensions Specification

## Purpose
TBD - created by archiving change browser-extensions. Update Purpose after archive.
## Requirements
### Requirement: Install a browser extension
Muninn SHALL let the user install a Web Extension from an unpacked folder (containing
`manifest.json`) or a packed `.zip` / `.crx` archive, unpacking it into Application Support and
loading it via `WKWebExtension`. The install list is persisted.

#### Scenario: install from an unpacked folder
- **WHEN** the user picks a folder containing `manifest.json` in Settings → Extensions → Add Extension…
- **THEN** the extension is copied into `~/Library/Application Support/Muninn/Extensions/`, loaded,
  enabled, and listed

#### Scenario: install from a .zip / .crx
- **WHEN** the user picks a `.zip` or `.crx` file
- **THEN** it is unpacked (the manifest located even if nested one level down), then loaded as above

#### Scenario: invalid bundle
- **WHEN** the chosen folder/archive has no `manifest.json`
- **THEN** installation fails with an explanatory alert and nothing is added

### Requirement: Run extensions in tabs
Enabled extensions SHALL run in browser tabs — content scripts inject on pages matching their
declared patterns (host access auto-granted), background service workers run, and the extension can
see and manipulate the browser's tabs and window through the standard extension APIs.

#### Scenario: content script injects
- **WHEN** an enabled extension declares a content script matching the current page
- **THEN** the content script runs on that page (on new tabs opened after the extension is enabled)

#### Scenario: tabs API reflects the real browser
- **WHEN** an extension queries or creates tabs
- **THEN** it sees Muninn's real tabs and can open/activate/close them

### Requirement: Extension action toolbar and popups
Muninn SHALL show a toolbar button for each loaded extension's action; activating it presents the
extension's popup (if it declares one) or fires the action's click event.

#### Scenario: open a popup
- **WHEN** the user clicks the action button of an extension that declares a default popup
- **THEN** the popup is presented anchored to the button

#### Scenario: popup-less action
- **WHEN** the user clicks the action button of an extension with no popup
- **THEN** the extension's action click event fires

### Requirement: Enable, disable, and remove extensions
Muninn SHALL let the user enable, disable, or remove each installed extension; state is persisted.

#### Scenario: disable
- **WHEN** the user turns an extension off
- **THEN** it is unloaded from the controller and stops running (persisted across launches)

#### Scenario: remove
- **WHEN** the user removes an extension (confirmed)
- **THEN** it is unloaded and its unpacked files are deleted

### Requirement: Preserve the Pass shim's clean MAIN world when no extensions are used
Muninn SHALL attach the `WKWebExtensionController` to a tab only when at least one extension is
enabled. Because attaching the controller injects a `browser` global into a page's MAIN world, this
keeps the page MAIN world clean (the Pass-shim S2 invariant) whenever no extensions are installed.

#### Scenario: no extensions installed
- **WHEN** no extension is enabled
- **THEN** the extension controller is not attached and a non-blessed page's MAIN world exposes no
  `browser` / `chrome` global

#### Scenario: extension enabled
- **WHEN** at least one extension is enabled
- **THEN** the controller is attached to newly created tabs so extensions run

