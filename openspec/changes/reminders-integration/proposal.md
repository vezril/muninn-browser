# Proposal: reminders-integration

**Apple Reminders** in Muninn — a Tools-sidebar tool plus commands, backed by **EventKit** (on-device,
no shim, no account). See, create, complete, edit, and delete reminders and lists; and turn the current
page into a reminder or a whole list.

## What it does

**Sidebar tool** (right Tools sidebar, `checklist` icon, alongside Calendar / Ask / Notifications):
- A **list picker** (popup) + **＋ New List** button.
- The selected list's reminders: **checkbox** to complete, **click title** to edit, **hover → ×** to
  delete, a **Completed** toggle to show/hide done items.
- An **add field** at the bottom (Enter adds to the current list).
- Requests Reminders access the first time it's shown; observes `.EKEventStoreChanged` so external
  edits (or our own commands) refresh live.

**Commands** (⌘N palette + **File → Reminders**):
- **Show Reminders** — reveal the tool.
- **New Reminder…** — quick add to the default list.
- **New Reminder from Page** — saves the current page's title + URL as a reminder (read-later / follow-up).
- **Create Reminders List from Page** — the recipe case. Extraction is **structured-first, model-fallback**:
  1. Parse schema.org **Recipe** JSON-LD (`recipeIngredient` / `recipeInstructions`). If both are present,
     ask **Ingredients or Steps**; otherwise use what's there. List name = recipe/page title.
  2. No structured data → ask the **local Ollama model** for a `{name, items}` list from the page text
     (tolerant of prose/```json fences). Requires a configured model; a clear toast if not.
  Then a new list is created and populated, and the tool is revealed focused on it.

## Design notes

- **EventKit, on-device.** `RemindersService` wraps a shared `EKEventStore`: full-access request,
  list/reminder CRUD, batch-add (single commit), create-list (inherits the default list's source).
- **Not `@MainActor`.** EventKit invokes `fetchReminders`' completion on its own background queue, so a
  MainActor-isolated completion trips a hard dispatch assertion (this crashed on first click during dev);
  the service is `@unchecked Sendable` and maps to Sendable `ReminderItem`s inside the completion.
- `Info.plist` gains `NSRemindersFullAccessUsageDescription`. App is non-sandboxed, so no entitlement is
  needed — macOS TCC prompts on first access.

## Scope / caveats

- Reminders only carry a **title** here (notes preserved on edit; no due-date/priority/subtask UI yet).
- Page → list depends on schema.org recipe data or a local model; arbitrary pages without either yield a
  "couldn't find a list" toast.

## Impact

New `Muninn/Reminders/` — `RemindersService`, `RemindersTool`, `PageListExtractor`. `AppShell` gains the
tool registration, `revealRemindersTool`, and the four command handlers; `AppDelegate` gains a File →
Reminders submenu; palette gains 5 entries. 92 XCTests green (+6 `PageListExtractorTests`); live-gated.
