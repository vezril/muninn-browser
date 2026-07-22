# Tasks: page-context

- [x] `ChatMessage.Role.system` for the injected context message
- [x] `AskChatView`: page-context toggle (📄) left of the input; highlight when on
- [x] On send with toggle on, fetch page context and prepend a `system` message (not shown / not persisted)
- [x] `AppShell.fetchPageContext` via `evaluateJavaScript("document.body.innerText")` on the active tab; ~12k cap
- [x] Live-verified (Calvin): "summarize this page" works
- [ ] Ship: full suite green; version bump + tag; OpenSpec archive
