# Tasks: new-tab-quotes

- [x] `QuoteVault` — scan folder for `source/quotes` notes; pure frontmatter parser (scalar/block/inline)
      + `[[wikilink]]`/quote cleaning with alias; cached @MainActor singleton, nonisolated parser.
- [x] `VaultQuote` carries title (quote), `author`, `from`.
- [x] `ObsidianSettings` — `quotesEnabled`, `quotesPath`, `quotesFolder`.
- [x] `AppShell` — `landingTagline()` (random quote → escaped HTML, — Author, From), `__MUNINN_TAGLINE__`
      substitution, `.quote`/`.author` CSS (theme-aware).
- [x] Settings → Obsidian: toggle + quotes-folder picker.
- [x] `QuoteVaultTests` (6): real note shape, author+from `[[ ]]` stripping, alias, scalar/inline forms,
      untagged/no-frontmatter/missing-author. Full suite green (116).
- [x] Live-gated (New Tab shows random quotes with attribution).
