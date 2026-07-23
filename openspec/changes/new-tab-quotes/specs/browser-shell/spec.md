# browser-shell

## ADDED Requirements

### Requirement: Random vault quote on New Tab
Muninn SHALL optionally display a random quote from the user's Obsidian vault on the New Tab page, using
notes tagged `source/quotes` (title = quote; frontmatter author/from as attribution with wikilink markup
stripped; body ignored), gated by a setting (default off).

#### Scenario: show a quote
- **WHEN** the setting is on and quote notes exist in the configured folder
- **THEN** the New Tab page shows a random quote with its author/source attribution instead of the tagline

#### Scenario: disabled or no quotes
- **WHEN** the setting is off or no quote notes are found
- **THEN** the New Tab page shows the default tagline
