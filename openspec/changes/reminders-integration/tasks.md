# Tasks: reminders-integration

- [x] `RemindersService` (EventKit) — access request, list/reminder CRUD, batch-add, create-list;
      non-MainActor + `@unchecked Sendable` (background completion isolation fix).
- [x] `RemindersTool` — list picker + ＋ New List, reminder rows (complete/edit/delete), Completed
      toggle, add field; permission-on-first-show; `.EKEventStoreChanged` live refresh.
- [x] `PageListExtractor` — schema.org Recipe JSON-LD extraction script + decode; tolerant model-list decode.
- [x] `AppShell` — register tool; `revealRemindersTool`; New Reminder / from Page / list-from-page
      (structured-first, local-model fallback); palette commands.
- [x] `AppDelegate` — File → Reminders submenu.
- [x] `Info.plist` — `NSRemindersFullAccessUsageDescription`.
- [x] Unit tests for the extractor/parse logic (`PageListExtractorTests`, 6). Full suite green (92).
- [x] Live gate: view lists/reminders, create/complete/edit/delete, ＋ New List, recipe → list.
      Confirmed working (Calvin, 2026-07-22); header-layout + first-click crash fixed along the way.
