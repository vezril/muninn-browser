# Proposal: new-tab-quotes

Option to show a **random quote from your Obsidian vault** on the New Tab page instead of the
"Private. Native. Yours." tagline.

## What it does

When enabled, the New Tab subtitle becomes a random quote drawn from vault notes tagged
**`source/quotes`**:
- The **note title (filename)** is the quote text.
- The frontmatter **`author`** and **`from`** (the source the quote is from) are the attribution,
  rendered "— Author, From". Both are **`[[wikilink]]`-stripped** (`[[Jonny Silverhand]]` → Jonny
  Silverhand; `[[Name|Alias]]` → Alias).
- The note **body is ignored** (personal notes stay private).

Each new tab picks a fresh quote; the folder scan is cached (5-min TTL) so opening many tabs is cheap.
Falls back to the default tagline when disabled or when no quotes are found.

## Configuration

**Settings → Obsidian**: a "Random quote on New Tab" toggle (default off) + a "Quotes folder
(source/quotes)" picker (blank = scan the whole vault).

## Design

- `QuoteVault` — recursively scans the folder for `.md` notes, filters by tag, extracts title/author/from.
  Frontmatter parsing (`frontmatterBlock` / `parseFrontmatter` / `clean`) is **pure + unit-tested**
  (scalar, block-list `- item`, and inline `[a, b]` YAML forms; quote + `[[…]]` cleaning with alias
  support). `@MainActor` singleton with cache; the parser functions are `nonisolated`.
- `ObsidianSettings` gains `quotesEnabled` / `quotesPath` / `quotesFolder`.
- `AppShell.landingTagline()` builds the quote HTML (escaped) and substitutes `__MUNINN_TAGLINE__` in the
  landing page; new `.quote` / `.author` CSS (theme-aware).

## Impact

New `Muninn/Obsidian/QuoteVault.swift`. Edits: `ObsidianSettings`, `AppShell` (landing tagline + CSS),
`SettingsWindowController` (toggle + folder). 116 XCTests green (+6 `QuoteVaultTests`, incl. Calvin's real
note shape); live-gated.
