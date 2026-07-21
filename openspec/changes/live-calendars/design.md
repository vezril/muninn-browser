# Design: live-calendars

## Data flow

```
Proton Calendar (user creates a read-only share link)
        │  https .ics  (public, unauthenticated)
        ▼
CalendarFeed (native URLSession, poll timer + focus refresh, last-good cache)
        │  raw text
        ▼
ICSParser  →  [VEvent]  (unfolded lines, VTIMEZONE table, RRULE/EXDATE/RDATE)
        │
        ▼
NextEvent.resolve(events, now)  →  Occurrence? (title, start, end, joinURL?)
        │
        ▼
LiveCalendarWidget (in ToolsSidebar)  →  countdown + Join → openRouted(joinURL)
```

Everything from `CalendarFeed` down is **pure/native** — no shim, no content world, no fetch
proxy. The fetch is an unauthenticated GET of a user-pasted URL, so the ground rule "never
handle Proton credentials" holds trivially.

## Components

- **`ToolsSidebar`** (AppKit view) — a right-hand panel mirroring the left sidebar's visual
  language (rounded card, workspace tint aware). A vertical `NSStackView` of tool views; MVP
  adds one. Toggle lives in the window chrome + a remappable `ShortcutAction.toolsSidebar`.
  Collapse state persisted (new field on the sidebar store, or a small `ToolsState`).
- **`LiveCalendar`** (Codable model) — `id`, `name`, `icsURL`, `leadTimeMinutes`. Persisted in
  `SidebarState` (app-wide, not per-workspace — a calendar is global).
- **`CalendarFeed`** (actor/`@MainActor` class) — owns the poll `Timer`, does `URLSession`
  fetch, hands text to `ICSParser`, publishes `[VEvent]` + fetch status; caches last good.
- **`ICSParser`** (pure) — line unfolding (RFC 5545 §3.1), property parsing, `VTIMEZONE`
  collection, `VEVENT` → `VEvent { uid, summary, dtstart, dtend/duration, allDay, tzid, rrule,
  exdates, rdates, raw fields for join extraction }`.
- **`Recurrence`** (pure) — expands a `VEvent` into occurrences within a bounded window
  (`now … now + 60d`, extended if none found). Implements `FREQ`/`INTERVAL`/`COUNT`/`UNTIL`/
  `BYDAY`/`BYMONTHDAY`/`BYMONTH`/`BYSETPOS`/`WKST`, minus `EXDATE`, plus `RDATE`.
- **`JoinLink`** (pure) — regex/heuristic over `CONFERENCE`, `URL`, `X-*-CONFERENCE`,
  `LOCATION`, `DESCRIPTION` for `meet.google.com`, `zoom.us/j/…`, `*.zoom.us`, Proton Meet,
  `teams.microsoft.com`.
- **`LiveCalendarWidget`** — the tool view: title, a countdown label driven by a shared 1 s/1 min
  ticking timer, and a Join button shown when `timeUntilStart ≤ leadTime && joinURL != nil`.

## Why native fetch (not the Pass fetch-proxy)

The fetch-proxy exists to give the extension **worker** CORS-bypassed access from a custom-scheme
origin. Here the fetcher is native Swift (`URLSession`) with no web origin and no CORS — it just
GETs a URL. Simpler, fully decoupled from the shim, and testable without the background host.

## Recurrence: the effort driver (chosen: full RFC 5545)

Recurring standups/syncs are the whole point of "next meeting," so partial recurrence would gut
the feature. Full RFC 5545 is the biggest single chunk of work and the richest source of edge
cases (time zones, `BYSETPOS`, `WKST`, `UNTIL` in UTC vs local, all-day arithmetic). Mitigation:
`ICSParser` + `Recurrence` + `NextEvent` + `JoinLink` are **pure functions**, so they get heavy
XCTest coverage from `.ics` **fixtures** (checked-in sample feeds incl. Proton-exported ones) with
zero network or GUI — this is where the correctness budget goes. If hand-rolling the full grammar
proves too costly, fall back to a **single-file vendored RRULE expander** (pure Swift, no network
dep — self-containment preserved); decision recorded during Task group 2.

## Multiple calendars

The settings model is a list. MVP resolves "next" as the **soonest occurrence across all
configured calendars**, and the widget shows that one. (A per-calendar stacked view is deferred.)

## Testability

Pure core → fixture-driven unit tests: one-off, DAILY/WEEKLY/MONTHLY, `INTERVAL`, `COUNT`,
`UNTIL`, `BYDAY`/`BYSETPOS`, `EXDATE` skip, all-day, cross-time-zone, and join-link extraction per
provider. Live gate (Calvin's real Proton share link) validates the end-to-end fetch + a real
recurring meeting — the authoritative check, since headless can't see his calendar.

## Open decisions (resolve at build)

- Persist the calendar list + tools-collapse in `SidebarState` vs a new `ToolsStore`
  (leaning `SidebarState` for one less file).
- Poll interval default (leaning 5 min) and whether to also refresh on network-reachability
  regain.
- Countdown tick cadence (1 s under ~2 min to feel live, else 1 min) to avoid needless redraws.
