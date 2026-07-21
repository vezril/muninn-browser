# live-calendars Specification

## Purpose
TBD - created by archiving change live-calendars. Update Purpose after archive.
## Requirements
### Requirement: A right-side Tools sidebar hosts utility widgets
Muninn SHALL provide a collapsible right-hand Tools sidebar that hosts a vertical stack of
tool widgets. Its shown/collapsed state SHALL persist across relaunch. In this change the
sidebar hosts exactly one tool, the Live Calendar.

#### Scenario: toggle the Tools sidebar
- **WHEN** the user toggles the Tools sidebar (from the window chrome or its shortcut)
- **THEN** the right panel shows or hides, the web content resizes to fit, and the state is
  remembered on next launch

#### Scenario: empty state
- **WHEN** the Tools sidebar is shown but no Live Calendar is configured
- **THEN** it shows a brief empty state pointing the user to Settings → Calendars

### Requirement: A Proton Calendar ICS share link is the data source
A Live Calendar SHALL be configured by a user-provided read-only ICS share link. Muninn SHALL
fetch that URL natively (no login, no credentials) on a poll interval and on window focus,
normalising `webcal://` to `https://`, and SHALL cache the last successful parse.

#### Scenario: fetch and parse a share link
- **WHEN** a valid Proton Calendar ICS share URL is configured
- **THEN** Muninn fetches it, parses the events locally, and drives the widget from them

#### Scenario: transient failure degrades gracefully
- **WHEN** a fetch fails (offline) or returns unparseable data
- **THEN** the widget keeps showing the last good next-event (marked stale if known) and
  retries on the next poll, without error dialogs

#### Scenario: no credentials are ever handled
- **WHEN** any calendar fetch occurs
- **THEN** it is an unauthenticated GET of the user-pasted public URL — Muninn never asks for,
  stores, or sends a Proton password, key, or session

### Requirement: The parser resolves the next event with full RFC 5545 recurrence
The ICS parser SHALL extract VEVENTs and compute the next upcoming occurrence relative to now,
correctly handling one-off events and recurring events per RFC 5545 — `RRULE`
(`FREQ`, `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY`, `BYMONTHDAY`, `BYMONTH`, `BYSETPOS`, `WKST`),
`EXDATE`, `RDATE` — plus `VTIMEZONE`/`TZID`, all-day (`VALUE=DATE`) events, and
`DTSTART`/`DTEND`/`DURATION`.

#### Scenario: next one-off event
- **WHEN** the feed has a single future event
- **THEN** the widget targets it

#### Scenario: next occurrence of a recurring event
- **WHEN** a weekly standup recurs and today's instance is upcoming
- **THEN** the next occurrence's date/time is computed correctly for the event's time zone

#### Scenario: a cancelled occurrence is skipped
- **WHEN** the next computed occurrence is listed in `EXDATE`
- **THEN** it is skipped and the following valid occurrence is used

#### Scenario: past events are ignored
- **WHEN** an event or occurrence is already over
- **THEN** it is not selected as "next"

### Requirement: The widget shows a live countdown and a Join button
The Live Calendar widget SHALL show the next event's title and a live countdown that updates
over time. When the event starts within the configured lead time AND a video-call link is
detected, a Join button SHALL appear; clicking it opens the call through the standard routing
path (composing with Air Traffic Control).

#### Scenario: countdown ticks
- **WHEN** the next event is in the future
- **THEN** the widget shows a decreasing countdown; at start it reads "now"; after end it
  advances to the following event

#### Scenario: Join appears within the lead time
- **WHEN** the event begins within the configured lead time and has a detected Meet/Zoom/Proton
  Meet/Teams link
- **THEN** a Join button appears and clicking it opens the meeting URL via `openRouted`

#### Scenario: no join link
- **WHEN** the next event has no detectable video-call link
- **THEN** the countdown shows but no Join button appears

### Requirement: Calendars are managed in Settings
The Settings window SHALL provide a Calendars section to add, edit (name, ICS URL, reminder
lead time), and remove Live Calendars, persisted across relaunch.

#### Scenario: add and remove a calendar
- **WHEN** the user adds a calendar with a name and ICS URL, sets a lead time, and later removes it
- **THEN** each change takes effect immediately and survives relaunch

