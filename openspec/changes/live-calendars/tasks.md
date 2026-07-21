# Tasks: live-calendars

Built one task-group at a time, with a gate between groups.

## Group 1 — Tools sidebar shell (right)  ✅
- [x] `ToolsSidebar` right panel (workspace-tint aware) + vertical tool stack
- [x] Show/hide toggle in window chrome (top-right `sidebar.right`) + `ShortcutAction.toolsSidebar` (⌘⌥T, remappable)
- [x] Web content resizes to the remaining width; collapse state persisted (`SidebarState.toolsSidebarOpen`)
- [x] Empty state ("Add a calendar in Settings → Calendars")
- **Gate:** ✅ Calvin — "Works well" (2026-07-21)

## Group 2 — ICS parser + recurrence (pure, the bulk)
- [ ] `ICSParser`: line unfolding, property/param parsing, `VTIMEZONE` table, `VEVENT` model
- [ ] `Recurrence`: `FREQ`/`INTERVAL`/`COUNT`/`UNTIL`/`BYDAY`/`BYMONTHDAY`/`BYMONTH`/`BYSETPOS`/`WKST`, `EXDATE`, `RDATE`
- [ ] `NextEvent.resolve` over a rolling window; all-day + `DURATION` handling; TZID/UTC
- [ ] `JoinLink` extraction (Meet / Zoom / Proton Meet / Teams)
- [ ] Fixture `.ics` files + XCTests for each recurrence + join case (incl. a Proton export)
- [ ] Decide: hand-rolled vs single-file vendored RRULE expander (record in design.md)
- **Gate:** unit tests green across the fixture matrix

## Group 3 — Feed fetcher
- [ ] `CalendarFeed`: `URLSession` GET, `webcal://`→`https://`, poll timer + focus refresh
- [ ] Last-good cache + graceful offline/parse-failure degradation
- [ ] `LiveCalendar` model persisted; "soonest across all calendars" resolution
- **Gate:** fetches a real Proton share link and surfaces the right next event (Calvin gate)

## Group 4 — Live Calendar widget
- [ ] Widget view: title + live countdown (tick cadence: 1 s under ~2 min, else 1 min)
- [ ] Join button gated by lead time + link presence → `openRouted` (composes with ATC)
- [ ] "now"/"ended"/advance-to-next states
- **Gate:** live countdown + Join verified against a real upcoming meeting (Calvin gate)

## Group 5 — Settings → Calendars
- [ ] New "Calendars" nav section: add / edit (name, ICS URL, lead time) / remove
- [ ] AppShell settings API for the calendar list
- **Gate:** add/edit/remove works and persists

## Ship
- [ ] Full suite green (existing 42 + new parser tests); clean build
- [ ] Live end-to-end gate (Calvin); OpenSpec archive; bump version + tag
