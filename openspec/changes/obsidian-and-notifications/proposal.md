# Proposal: obsidian-and-notifications

Two features built together this session.

## Obsidian integration

An Obsidian vault is a folder of Markdown files, so "integration" = writing `.md` notes into a
configured folder.

- **Settings → Obsidian:** Vault location + New notes location (folder pickers; new-notes defaults
  to the vault root).
- **⌘N → "New Note from Page (Obsidian)":** writes a note (YAML frontmatter — `title`, `url`,
  `created`, `source`, `tags: [web-clip]` — a `# Title` heading, and the URL), then opens it in
  Obsidian (`obsidian://open?path=…`).
- **⌘N → "Summarize Page → Obsidian Note"** (only when a local model is configured): fully
  automatic — grabs the page text, has Ollama write a TL;DR + bullets (no chat UI), saves the
  note, and toasts when done.

Commands appear only once a vault is configured; the summarize command additionally requires a
configured Ollama model.

## Notifications history

Toasts are transient — a missed one was gone. Now they're recorded.

- A **Notifications tool** in the Tools sidebar (third tool; the switcher went icon-only to fit)
  lists shown toasts (message + relative time), newest first.
- **Auto-clear** past a configurable window (**Settings → General → "Keep notifications for"**:
  1h/6h/1d/7d/Until Cleared, default 1 day) — pruned on launch, every ~5 min, and on each add.
- **Manual clear** (trash button). Persisted to `notifications.json`.
- `showToast(record:)` records by default; progress toasts (e.g. "Summarizing page…") pass
  `record: false`.

## Impact

New: `ObsidianSettings`/`ObsidianNote`, `NotificationStore`/`AppNotification`/
`NotificationRetention`, `NotificationsView`; Settings gains Obsidian + a General retention row;
`AppShell` gains the note flows, a shared `currentPageText`, the notification store, and the third
tool; `ToolsSidebar` switcher is icon-only. Ollama's `fetchPageContext` now reuses
`currentPageText`. Note-writer covered by unit tests. No shim changes.
