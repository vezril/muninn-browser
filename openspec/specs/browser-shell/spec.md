# browser-shell Specification

## Purpose
TBD - created by archiving change chrome-qol. Update Purpose after archive.
## Requirements
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

### Requirement: Preferred website language
Muninn SHALL let the user choose the language websites detect (default English), applied via the
`Accept-Language` header and by overriding `navigator.language`/`navigator.languages`, so a foreign
IP/locale doesn't change the site language.

#### Scenario: default English
- **WHEN** the user has not changed the setting
- **THEN** websites see English (`Accept-Language` en + `navigator.language` en-US)

#### Scenario: change language
- **WHEN** the user picks a language in Settings → General
- **THEN** new tabs' `navigator.language` reflects it immediately, and the `Accept-Language` header
  reflects it after the next launch

#### Scenario: IP-based content unaffected
- **WHEN** a site serves a language by IP geolocation for legal compliance (not browser language)
- **THEN** that content is not changed by this setting

### Requirement: Rename a tab
Muninn SHALL let the user give a tab a custom display name that overrides the page title in the
sidebar without changing the tab's content, resettable, and persisted for pinned/favourite tabs.

#### Scenario: rename
- **WHEN** the user right-clicks a tab, chooses Rename…, and enters a name
- **THEN** the sidebar shows that name while the page (and its live title underneath) is unchanged

#### Scenario: reset
- **WHEN** the user chooses Reset Name
- **THEN** the sidebar shows the live page title again

#### Scenario: persists
- **WHEN** a pinned/favourite tab has a custom name and Muninn is relaunched
- **THEN** the custom name is restored

### Requirement: Pinned tabs reopen at their pin
A pinned or favourite tab SHALL reopen at its pinned link (`homeURL`) after being closed/unloaded and
after a relaunch, regardless of where it was last navigated. Regular tabs keep their last location.

#### Scenario: close and reopen
- **WHEN** the user navigates a pinned tab away from its pin, closes it (Cmd+W), then reopens it
- **THEN** it loads the original pinned link, not the last-visited URL

### Requirement: Task Manager
Muninn SHALL provide a Task Manager window listing each tab with a running WebContent process, showing
its memory and responsiveness, refreshed periodically, with actions to focus, reload, or close a tab.

#### Scenario: list tabs by memory
- **WHEN** the user opens the Task Manager
- **THEN** each tab with a live process is listed with its memory and status, sorted by memory
  (largest first), updating every few seconds

#### Scenario: unresponsive tab flagged
- **WHEN** a tab does not answer a responsiveness ping within a few seconds
- **THEN** it is shown as "Not responding"

#### Scenario: act on a tab
- **WHEN** the user selects a row and chooses Switch to Tab / Reload / Close Tab
- **THEN** that tab is focused / reloaded / closed

### Requirement: On-device page translation
Muninn SHALL provide an on-demand action to translate the active page's main-frame text into the
user's preferred website language using an on-device translation engine, such that no page content
leaves the device, with the ability to restore the original text.

#### Scenario: translate a foreign-language page
- **WHEN** the user invokes Translate Page on a page whose detected language differs from the preferred
  website language
- **THEN** the page's visible text is translated in place into the preferred language, entirely on-device

#### Scenario: already in the target language
- **WHEN** the user invokes Translate Page on a page already in the preferred language
- **THEN** the page is left unchanged and the user is told it is already in that language

#### Scenario: restore original
- **WHEN** the user invokes the action again on a translated page
- **THEN** the original text is restored from the cached originals

#### Scenario: unsupported language
- **WHEN** translation for the page's language is not available on the device
- **THEN** the user is informed and the page is left unchanged

### Requirement: Apple Reminders integration
Muninn SHALL integrate with Apple Reminders on-device (EventKit), providing a sidebar tool to view and
manage reminders and lists, and commands to create reminders and lists — including from the current page.

#### Scenario: view and manage reminders in the sidebar
- **WHEN** the user opens the Reminders tool and grants access
- **THEN** the selected list's reminders are shown, and the user can complete, edit, delete, and add
  reminders, switch lists, and create a new list

#### Scenario: reminder from the current page
- **WHEN** the user invokes "New Reminder from Page"
- **THEN** a reminder capturing the page's title and URL is added to the default list

#### Scenario: list from the current page
- **WHEN** the user invokes "Create Reminders List from Page" on a page with recognizable list content
  (e.g. a recipe)
- **THEN** a new list is created and populated from the page's structured recipe data, or from a local
  model when no structured data is present, and the tool is shown focused on the new list

#### Scenario: access declined
- **WHEN** Reminders access has not been granted
- **THEN** the user is told how to enable it and no reminders are shown

### Requirement: Share-link tracker stripping
Muninn SHALL remove tracking and attribution parameters from a URL when the user copies or shares it,
without altering the page being viewed, gated by a setting (default on).

#### Scenario: strip platform share tokens
- **WHEN** the user copies or shares a link carrying platform share-attribution parameters (e.g. a
  YouTube link with `si`)
- **THEN** the copied/shared link has those parameters removed

#### Scenario: preserve meaningful parameters
- **WHEN** the shared link also carries meaningful parameters (e.g. a YouTube timestamp `t`, a playlist
  `list`, a Reddit `context`)
- **THEN** those parameters are kept

#### Scenario: setting off
- **WHEN** the strip-trackers-from-shared-links setting is off
- **THEN** links are copied and shared unmodified

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

### Requirement: Video download
Muninn SHALL let the user download the video on the current page (best video, or audio-only) on supported
video sites, showing progress and recording the result in the Library, using an external downloader
(yt-dlp/ffmpeg) when available.

#### Scenario: download a video
- **WHEN** the user activates the download-video control on a supported video site
- **THEN** the page's video downloads to the profile's download folder, with progress shown, and is
  recorded in the Library on completion

#### Scenario: audio only
- **WHEN** the user chooses the audio-only option
- **THEN** the audio is downloaded as an MP3

#### Scenario: downloader unavailable
- **WHEN** the external downloader is not installed
- **THEN** the control is hidden and the user is told what to install

### Requirement: Library item actions
Muninn SHALL provide a right-click menu on Library items with Open, Show in Finder, Copy Path, Move to
Trash (recoverable), and Remove from List.

#### Scenario: reveal a download
- **WHEN** the user right-clicks a download and chooses Show in Finder
- **THEN** the file is revealed in Finder

### Requirement: Toolbar control reliability
The nav toolbar controls SHALL remain fully clickable at every allowed sidebar width, and the settings
control SHALL open the Settings window.

#### Scenario: settings at a narrow sidebar
- **WHEN** the sidebar is at its minimum width and the user clicks the settings control
- **THEN** the whole control is clickable and the Settings window opens

### Requirement: Pomodoro timer
Muninn SHALL provide a customizable Pomodoro timer as a Tools-sidebar tool, cycling focus and break
phases with a visible countdown, controls to start/pause/reset/skip, and phase-change alerts.

#### Scenario: run a focus/break cycle
- **WHEN** the user starts the timer
- **THEN** the current phase counts down, and on reaching zero it advances to the next phase (a long break
  after every configured number of focus sessions) with a sound and a notification

#### Scenario: customize durations
- **WHEN** the user changes the focus/break durations, long-break interval, or auto-start setting
- **THEN** the timer uses and persists those settings

#### Scenario: alert while in another app
- **WHEN** a phase completes while Muninn is in the background and notifications are permitted
- **THEN** a system notification announces the transition

### Requirement: Most-recently-used tab on close
When the active tab is closed, Muninn SHALL activate the most-recently-used remaining tab in the
workspace, rather than the first tab in the list.

#### Scenario: close returns to the previous tab
- **WHEN** the user closes the active tab
- **THEN** the tab they were on just before it becomes active

### Requirement: Random vault quote on New Tab
Muninn SHALL optionally display a random quote from the user's Obsidian vault on the New Tab page, using
notes tagged `source/quotes` (title = quote; frontmatter author/from as attribution with wikilink markup
stripped; body ignored), gated by a setting (default off).

#### Scenario: show a quote
- **WHEN** the setting is on and quote notes exist in the configured folder
- **THEN** the New Tab page shows a random quote with its author/source attribution instead of the tagline

#### Scenario: disabled or no quotes
- **WHEN** the setting is off or no quote notes are found
- **THEN** the New Tab page shows the default tagline

### Requirement: Tools pane hover-peek
The right Tools pane SHALL reveal on hovering the window's right edge when collapsed (as a floating
overlay that retracts when the cursor leaves), and its show/hide toggle SHALL live inside the pane.

#### Scenario: peek on right-edge hover
- **WHEN** the Tools pane is collapsed and the cursor reaches the right edge
- **THEN** the pane slides in as a floating overlay, and retracts when the cursor leaves it

#### Scenario: pin from the pane
- **WHEN** the user clicks the toggle inside the Tools pane
- **THEN** the pane pins open (or collapses if already open), and the pinned state persists

