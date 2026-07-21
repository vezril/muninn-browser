# Tasks: live-calendars

Built one task-group at a time, with a gate between groups.

## Group 1 — Tools sidebar shell (right)  ✅
- [x] `ToolsSidebar` right panel (workspace-tint aware) + vertical tool stack
- [x] Show/hide toggle in window chrome (top-right `sidebar.right`) + `ShortcutAction.toolsSidebar` (⌘⌥T, remappable)
- [x] Web content resizes to the remaining width; collapse state persisted (`SidebarState.toolsSidebarOpen`)
- [x] Empty state ("Add a calendar in Settings → Calendars")
- **Gate:** ✅ Calvin — "Works well" (2026-07-21)

## Group 2 — ICS parser + recurrence (pure, the bulk)  ✅
- [x] `ICSParser`: line unfolding, property/param parsing, TZID via Foundation, `VEVENT` model
- [x] `Recurrence`: `FREQ`/`INTERVAL`/`COUNT`/`UNTIL`/`BYDAY`/`BYMONTHDAY`/`BYMONTH`/`BYSETPOS`/`WKST`, `EXDATE`, `RDATE`
- [x] `Recurrence.nextOccurrence` over a rolling window; all-day + `DURATION` handling; TZID/UTC
- [x] `JoinLink` extraction (Meet / Zoom / Proton Meet / Teams / Webex / Whereby)
- [x] 19 fixture XCTests (recurrence matrix + join cases) — all green
- [x] Decided: hand-rolled expander; **TZID resolved via Foundation `TimeZone`** (IANA db) rather
      than parsing VTIMEZONE offset rules — correct in practice, far less code (recorded in design.md)
- **Gate:** ✅ unit tests green (19/19)

## Group 3 — Feed fetcher  ✅
- [x] `CalendarFeed`: native `URLSession` GET, `webcal://`→`https://`, poll timer (+ refresh on panel open)
- [x] Last-good cache per calendar + graceful offline/parse-failure degradation
- [x] `LiveCalendar` model persisted (`SidebarState.liveCalendars`); "soonest across all calendars"

## Group 4 — Live Calendar widget  ✅
- [x] Widget view: title + time + live countdown (1 s tick), workspace-tinted panel host
- [x] Join button gated by lead time + link presence → `openRouted` (composes with ATC)
- [x] "now"/"ended"/advance-to-next + "No upcoming events" states

## Group 5 — Settings → Calendars  ✅
- [x] New "Calendars" nav section: add / edit (name, ICS URL, lead time) / remove
- [x] AppShell settings API (`settingsLiveCalendars`/`settingsAddCalendar`/…)

## Ship
- [x] Live end-to-end gate — Calvin: "looks good" against his real Proton calendar (2026-07-21)
- [ ] Full suite green; clean build; OpenSpec archive; bump version + tag
