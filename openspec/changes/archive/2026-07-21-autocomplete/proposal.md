# Proposal: autocomplete

## Why

Fast navigation: typing "you" should suggest "youtube.com" inline, accepted with Tab — for
both the address bar and the new-tab search.

## What Changes

- **`HistoryStore`** now counts **visits** (frequency, the "cache") per URL and exposes
  `rankedHosts()` (deduped bare hosts ranked by visits then recency) + `bestCompletion(for:)`.
- **Address bar** — inline autocomplete: as you type at the end of the field, it completes to
  the best history host with the suffix selected; **Tab / →** accepts, keep typing to refine,
  **Enter** navigates. No completion while deleting.
- **New-tab search** — the landing page gets the ranked hosts injected and the same inline
  autocomplete (input selection + Tab/→ to accept).

## Impact

`HistoryStore` (visits + ranking/completion API); `AppShell` gains an `NSTextFieldDelegate`
autocomplete on the address field and injects hosts + autocomplete JS into the landing page.
Suggestions come only from visited sites (empty on a fresh profile).
