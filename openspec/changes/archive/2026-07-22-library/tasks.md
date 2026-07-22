# Tasks: library

- [x] `DownloadStore`/`DownloadRecord` → `downloads.json`; `InjectionCoordinator.onDownloadFinished` + didFinish/didFail
- [x] Context-menu capture (injected listener → `ContextMenuHandler`) + `MuninnWebView` "Save Image"/"Download Linked File" (tracked via `startDownload`); remove native "Download Image"
- [x] `LibraryPane` — left overlay, workspace-tinted, rounded, slide-in; Downloads list + Media grid; open/reveal/remove; dismiss
- [x] Sidebar 📚 button beside the workspace switcher; `HoverIconButton` hover cue
- [x] Drop animation (vertical) into the button + accent flash on download finish
- [x] Live-verified (Calvin): tracked image save, pane tint/rounding/slide, hover cue, drop
- [ ] Ship: full suite green; version bump + tag; OpenSpec archive
