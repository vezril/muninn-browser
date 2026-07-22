# obsidian-integration

## ADDED Requirements

### Requirement: Configure an Obsidian vault
Settings SHALL let the user set a vault folder and a new-notes folder (defaulting to the vault
root). Note commands appear only when a vault is configured.

#### Scenario: configure vault
- **WHEN** the user picks a vault folder in Settings → Obsidian
- **THEN** the Obsidian note commands become available in the command palette

### Requirement: Create a note from the current page
The user SHALL be able to create a Markdown note for the current page, with frontmatter
(`title`, `url`, `created`, `source`, tags) and the URL, opened in Obsidian.

#### Scenario: new note from page
- **WHEN** the user runs "New Note from Page (Obsidian)"
- **THEN** a `.md` note is written into the notes folder (filename sanitised + de-duplicated) and
  opened in Obsidian, and a toast confirms it

#### Scenario: not configured
- **WHEN** no vault is set
- **THEN** the command is absent (and any attempt shows a toast pointing to Settings → Obsidian)

### Requirement: Summarize a page into a note automatically
When a local model is configured, the user SHALL be able to summarize the current page into a new
note fully automatically (no chat interaction), with a toast on completion.

#### Scenario: summarize to note
- **WHEN** the user runs "Summarize Page → Obsidian Note"
- **THEN** the page text is summarized by the local model and saved as a note (frontmatter +
  summary + URL) with no chat UI, and a toast confirms when it's written

#### Scenario: requires a model
- **WHEN** no local model is configured
- **THEN** the summarize command does not appear
