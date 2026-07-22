# Proposal: ollama-connection

## Why

Muninn is local-first; running prompts against a **local** model (Ollama) keeps that promise —
nothing leaves the machine. This adds the connection config, a native client, and a first
consumer to actually use it.

## What

1. **Settings → Models** — a new section: Ollama base URL (default `http://localhost:11434`),
   **Test Connection** (lists installed models live), and a **Default model** picker. Persisted.
2. **`OllamaClient`** — native `URLSession`: `GET /api/tags` (models) and streaming
   `POST /api/chat` (multi-turn) + `POST /api/generate`, NDJSON parsed incrementally.
3. **Ask (chat) tool in the Tools sidebar** — a **non-blocking** chat panel (not a modal
   popup): send a message and the reply **streams in while you keep browsing**. Multi-turn
   (uses `/api/chat`). **Persists sessions** to `chat.json` (survives closing the window), with a
   **session switcher**, **New Session**, and **Clear**. A **typing indicator** (. → .. → …)
   shows while waiting for the first token. The **Tools sidebar is now multi-tool** (Calendar /
   Ask switcher) — the generalization anticipated when the calendar shipped.
4. **⌘N → "Ask Local Model…"** opens the Tools sidebar to the Ask tool and focuses the input.

## Design notes

- **Non-blocking by construction:** streaming runs on an async `URLSession` task; the chat lives
  in the right Tools panel, so a slow model never blocks the window. (Replaced an initial modal
  popup after it blocked the UI during generation.)
- **No shim, no credentials:** the daemon is local; the client is plain native networking.

## Scope / non-goals

- No page context yet — the chat is a plain conversation (feeding the current tab's text into a
  prompt is the natural follow-up).
- No model management (pull/delete) — Ollama's own CLI handles that.

## Impact

New: `OllamaClient` + `OllamaSettings`, `ChatStore`/`ChatSession`/`ChatMessage`, `AskChatView`,
a Settings → Models section, and a generalized multi-tool `ToolsSidebar` (`setTools`/`selectTool`
replacing the single-tool `setTool`). `AskChatView` streams via an `AppShell` `runChat` closure.
Parsers unit-tested. No shim/background changes.
