# Proposal: live-calendars

## Why

Arc's "Live Calendars" turns a pinned Google Calendar into a live countdown to your next
meeting with a one-click **Join** button. It's genuinely useful, but Arc gets its data from
Google Calendar's OAuth API — a path **Proton Calendar does not offer**: no public API, no
OAuth, no CalDAV, and end-to-end encryption means the servers hold only ciphertext
(`research/live-calendars-feasibility-2026-07-21.md`). The one supported, credential-free,
privacy-preserving way to read a Proton calendar from outside its own client is a **read-only
ICS share link** — a URL the user generates in Proton Calendar that any app may fetch and
parse. This change builds the Live Calendars experience on that feed.

It also introduces a **right-side Tools sidebar** as the home for the widget — a stackable
panel of utilities (Live Calendar is the first) that keeps the left navigation uncluttered
and gives future tools a place to live.

## What

Two things:

1. **Tools sidebar (right).** A collapsible right-hand panel (`ToolsSidebar`) that hosts
   stacked tool widgets, toggled from the window chrome; collapse state persists. MVP ships
   exactly one tool: the Live Calendar.

2. **Live Calendar widget (Option B — ICS feed).** The user pastes a Proton Calendar
   **read-only share link** into Settings. Muninn fetches that `.ics` natively on a poll
   interval, parses it locally, computes the **next upcoming event**, and renders the event
   title with a **live countdown**. When the event is within a configurable **lead time** and
   carries a video-call link, a **Join** button appears that opens the call (via `openRouted`,
   so it composes with Air Traffic Control).

## Scope (this change)

- **`ToolsSidebar`** — right panel + show/hide toggle + persisted collapse; a simple vertical
  stack of tool views. Minimal chrome to match the left sidebar's visual language.
- **ICS parsing** (`ICSParser`) — VEVENT extraction with **full RFC 5545 recurrence**: RRULE
  (`FREQ`/`INTERVAL`/`COUNT`/`UNTIL`/`BYDAY`/`BYMONTHDAY`/`BYMONTH`/`BYSETPOS`/`WKST`),
  `EXDATE`, `RDATE`, `VTIMEZONE`/`TZID`, all-day (`VALUE=DATE`), `DTSTART`/`DTEND`/`DURATION`.
  Pure and fixture-tested — no network or GUI needed.
- **`CalendarFeed`** — native `URLSession` GET of the user's ICS URL (`webcal://` → `https://`),
  on a poll interval + on window focus; caches the last good parse; degrades gracefully when
  offline or unparseable.
- **Next-event + join extraction** — expand occurrences over a rolling window to find the next
  event; extract a join link from `CONFERENCE`/`URL`/`LOCATION`/`DESCRIPTION` (Google Meet,
  Zoom, Proton Meet, Teams heuristics).
- **Live Calendar widget** — title + live countdown (ticks down; "now"/"ended" states) + Join
  button gated by lead time and link presence; click → `openRouted`.
- **Settings** — add / edit / remove a Live Calendar (name + Proton share ICS URL + reminder
  lead time), in a new **Calendars** section of the Settings window.

**Deferred:** multiple simultaneous calendars merged into one "next" (MVP supports a list but
shows the soonest across them — see design); writing/RSVP; free/busy-only links that hide
details; a left-sidebar tile badge (the Tools sidebar is the chosen surface); tools other than
the calendar.

## Impact

New: `ToolsSidebar`, `ICSParser`, `CalendarFeed`, `LiveCalendar` model, the widget view, and a
Calendars settings section. `SidebarState` (or a sibling store) gains the calendar list +
tools-collapse state. `AppShell` gains the right panel in its layout and a `perform`/menu
toggle. **No shim/background changes** — the fetch is native `URLSession` of a user-pasted
public URL, so the Pass fetch-proxy and content worlds are untouched. Composes with Air
Traffic Control (Join routes through `openRouted`).

## Ground rules

Never handles Proton credentials: the ICS share link is user-generated and read-only, and
Muninn only GETs that public URL — no login, no key handling, no vault/mail access. The
countdown/Join surface shows only what the user's own share link exposes.
