# Proposal: settings

## Why

A place to control browser preferences — starting with the search engine, default-browser
registration, and clearing a profile's data.

## What Changes

- **Settings gear** on the right of the URL bar → a menu:
  - **Search Engine** ▸ DuckDuckGo / Google / Bing (persisted; `SearchEngine.current`). Drives the
    **address bar**, **command bar**, and **new-tab search** consistently.
  - **Set as Default Browser…** (requests the OS default).
  - **Clear This Profile's Data…** — with confirmation, wipes the current profile's history +
    website data (cookies/logins/cache); other profiles untouched.
- **Address bar now searches:** non-URL input runs a search with the configured engine (it
  previously only handled URLs). New-tab landing page uses the engine's search action.

## Impact

New `SearchEngine` (enum + persisted setting); `AppShell` gains the gear button + settings menu
+ actions and wires the engine into `navigate`, the command palette, and the landing page;
`HistoryStore.clear()`; `CommandPalette.searchEngineName`.
