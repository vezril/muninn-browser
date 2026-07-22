# Tasks: share-link-cleaning

- [x] `ShareLinkCleaner` — host-scoped share-param rules + Amazon path cleanup; reuses `QueryStripper`
      for global click-IDs/UTM.
- [x] `ShieldsManager.cleanSharedLinks` toggle (default on).
- [x] `AppShell.shareURL()` applied to Copy Link, Copy as Markdown, Share button, toast Share.
- [x] Settings → Shields: "Strip trackers from copied & shared links" toggle.
- [x] `ShareLinkCleanerTests` (11), incl. the youtu.be `?si=` example; full suite green (103).
- [x] Live gate: copy/share a real YouTube (si), X, Amazon link → trackers gone, timestamp kept.
      Confirmed working (Calvin, 2026-07-22).
