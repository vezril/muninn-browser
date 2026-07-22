# Tasks: page-translation

- [x] `PageTranslator` — offscreen SwiftUI host driving `TranslationSession`; chunked batch; language
      detection (`NLLanguageRecognizer`); availability check; Sendable-safe actor bridge.
- [x] `PageTranslationScript` — extract (by-reference text-node capture), reinject-by-index, revert,
      translated-state probe.
- [x] `AppShell` — Translate toolbar button in the nav cluster; extract→detect→translate→reinject flow;
      already-in-target and error toasts; revert; icon reflects translated state (`updateChrome`).
- [x] `AppShell` palette command "Translate Page"; `AppDelegate` File → Translate Page.
- [x] Attach the translation host to the window on `present()`.
- [x] Build (Swift 6 concurrency clean) + full test suite green (86).
- [x] Live gate: translate a real French page (e.g. lemonde.fr) → English; verify Show Original reverts;
      confirm a model download prompt on first use. **Confirmed working (Calvin, 2026-07-22).**
