# Tasks: obsidian-and-notifications

## Obsidian
- [x] `ObsidianSettings` (vault + notes path) + `ObsidianNote` (frontmatter, sanitise, de-dupe, `obsidian://` open)
- [x] Settings → Obsidian section (folder pickers)
- [x] `AppShell.newNoteFromPage` + `summarizePageToNote` (auto Ollama summary → note → toast); shared `currentPageText`
- [x] Palette commands (gated on vault / model); unit tests for the note writer (3)

## Notifications
- [x] `NotificationStore`/`AppNotification`/`NotificationRetention`; `notifications.json`
- [x] `NotificationsView` tool (list + relative time + clear); registered as the 3rd Tools-sidebar tool (icon-only switcher)
- [x] `showToast(record:)` records real toasts; retention setting in Settings → General; prune on launch/timer/add

## Ship
- [x] Live-verified (Calvin): notes created + opened in Obsidian, summary note, notifications stack + clear
- [ ] Full suite green; version bump + tag; archive
