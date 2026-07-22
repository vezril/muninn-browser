# Proposal: page-context

## Why

The Ask chat (Ollama) was a plain conversation with no awareness of the page — so
"summarize this page" couldn't work. This gives the local model the current page's content on
demand.

## What

A **page-context toggle** (📄) left of the Ask input. When on, sending a message attaches the
**current tab's** title, URL, and visible text as a hidden `system` message prepended to the
turn's payload. It stays on for follow-ups and always reflects the currently active tab (browse
elsewhere and keep asking). The page text is capped (~12k chars) to fit local context windows.
The attached context is not shown as a bubble and is not persisted in the session — it's derived
fresh from the active tab at each send.

## Impact

`ChatMessage.Role` gains `system`. `AskChatView` gains the toggle + a `fetchPageContext` closure;
`AppShell` provides it via `evaluateJavaScript("document.body.innerText")` on the active web view.
No new persistence, no shim changes. Everything stays local (the text goes only to the local
Ollama daemon).

## Non-goals

- No smart extraction/readability pass yet (raw `innerText`, truncated) — good enough for
  summaries; a cleaner extraction is a later refinement.
