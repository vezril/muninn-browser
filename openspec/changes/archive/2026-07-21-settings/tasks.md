# Tasks: settings

## 1. Search engine

- [x] 1.1 `SearchEngine` (DuckDuckGo/Google/Bing) + persisted `current`; wire into `navigate` (search non-URL input), command palette, and the landing page.

## 2. Settings menu

- [x] 2.1 Gear button on the right of the URL bar → menu: Search Engine ▸, Set as Default Browser…, Clear This Profile's Data….
- [x] 2.2 `HistoryStore.clear()` + `WKWebsiteDataStore.removeData` for the current profile (with confirmation).

## 3. Ship

- [x] 3.1 Full suite green; ship PR-gated; update `CLAUDE.md`; cut version.
