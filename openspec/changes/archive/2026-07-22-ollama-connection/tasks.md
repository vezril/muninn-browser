# Tasks: ollama-connection

- [x] `OllamaClient` (native URLSession): `/api/tags`, streaming `/api/chat` + `/api/generate`; `OllamaSettings`
- [x] Settings → Models: base URL, Test Connection (lists models), default-model picker
- [x] `ChatStore`/`ChatSession`/`ChatMessage` — persist sessions to `chat.json`
- [x] `AskChatView` — non-blocking chat: streamed bubbles, session switcher, New Session, Clear
- [x] Typing indicator (. → .. → …) until the first token
- [x] Generalize `ToolsSidebar` to multiple tools (`setTools`/`selectTool`) + Calendar/Ask switcher
- [x] ⌘N → "Ask Local Model…" reveals the Ask tool; `AppShell.runChat` streams via OllamaClient
- [x] Unit tests: `/api/tags` + `/api/chat` + `/api/generate` NDJSON parsing (8 tests)
- [x] Live-verified (Calvin): send/stream, non-blocking, typing dots, bubble layout
- [ ] Ship: full suite green; version bump + tag; OpenSpec archive
