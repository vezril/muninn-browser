# ollama-connection

## ADDED Requirements

### Requirement: Configure a local Ollama connection
Settings SHALL provide a Models section to set the Ollama base URL, test the connection (listing
installed models), and choose a default model. Settings SHALL persist.

#### Scenario: test the connection
- **WHEN** the user enters a reachable Ollama URL and clicks Test Connection
- **THEN** the installed models are listed and the default-model picker is populated

#### Scenario: unreachable daemon
- **WHEN** the URL is wrong or Ollama isn't running
- **THEN** Test Connection reports an error (no crash)

### Requirement: Ask a local model from a non-blocking chat panel
The "Ask" tool (Tools sidebar) SHALL let the user chat with the default local model, streaming the
reply WITHOUT blocking the browser. The conversation SHALL be multi-turn.

#### Scenario: streamed reply while browsing
- **WHEN** the user sends a message
- **THEN** their message shows immediately and the model's reply streams into the bubble while the
  rest of the window stays fully usable

#### Scenario: waiting indicator
- **WHEN** a reply is pending (before the first token)
- **THEN** the assistant bubble shows an animated “. → .. → …”, replaced by the text once it arrives

#### Scenario: not configured
- **WHEN** no default model is set (or the daemon is unreachable)
- **THEN** the chat shows an inline error pointing to Settings → Models

### Requirement: Chat sessions persist and are manageable
Chat sessions SHALL persist across window close, and the user SHALL be able to switch sessions,
start a New Session, and Clear the current one.

#### Scenario: resume after closing
- **WHEN** the user closes and reopens the window
- **THEN** the previous conversation is still there

#### Scenario: new / clear
- **WHEN** the user starts a New Session or Clears the current one
- **THEN** a fresh conversation begins (or the current one empties), and past sessions remain
  selectable from the switcher

### Requirement: The Tools sidebar hosts multiple tools
The Tools sidebar SHALL host more than one tool with a switcher (Calendar / Ask).

#### Scenario: switch tools
- **WHEN** the user picks a tool in the Tools-sidebar switcher
- **THEN** that tool's view is shown in the panel
