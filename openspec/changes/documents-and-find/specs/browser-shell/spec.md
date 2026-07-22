# browser-shell

## ADDED Requirements

### Requirement: Open local files
Muninn SHALL open local files — via an address-bar path or `file://` URL, and via drag-and-drop onto the
web view — loading them with the read access WKWebView requires.

#### Scenario: address-bar path
- **WHEN** the user enters an absolute path, a `~` path, or a `file://` URL
- **THEN** Muninn loads that local file

#### Scenario: drag a file in
- **WHEN** the user drops a file onto the web view
- **THEN** Muninn opens it in a new tab, while non-file drags still reach the page

### Requirement: Built-in JSON viewer
Muninn SHALL render a JSON document as a prettified, syntax-coloured, collapsible view with Pretty/Raw,
Expand/Collapse, and Copy, gated by a setting (default on), without affecting non-JSON pages.

#### Scenario: view a JSON document
- **WHEN** a document is JSON (by content type or `.json` URL) and parses successfully
- **THEN** it is shown as a colour-coded, collapsible tree instead of raw text

#### Scenario: non-JSON untouched
- **WHEN** a document is not valid JSON
- **THEN** it renders normally

### Requirement: Download a viewed document
Muninn SHALL let the user download the document currently being viewed — including an inline PDF — into
the download folder and record it in the Library, via keyboard, menu, right-click, and the native PDF
control.

#### Scenario: save the current PDF
- **WHEN** the user invokes Save Page / Download PDF (⌘S, menu, right-click, or the inline PDF download control)
- **THEN** the document is saved to the download folder and recorded in the Library

### Requirement: Find in page
Muninn SHALL provide an in-page find bar (⌘F) that highlights matches, navigates next/previous, shows a
match count, and closes on Escape.

#### Scenario: search the page
- **WHEN** the user opens find and types a query
- **THEN** matches are highlighted with a count, and next/previous navigate between them
