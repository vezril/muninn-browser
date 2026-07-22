# page-context

## ADDED Requirements

### Requirement: Attach the current page as context to Ask messages
The Ask chat SHALL provide a toggle that, when on, attaches the current tab's title, URL, and
visible text to the message as context for the local model. The attached context SHALL reflect
the currently active tab at send time and is not shown as a chat bubble.

#### Scenario: summarize the page
- **WHEN** the page toggle is on and the user asks "summarize this page"
- **THEN** the model receives the current tab's content and answers about it

#### Scenario: follows the active tab
- **WHEN** the toggle stays on and the user switches to a different tab before asking again
- **THEN** the newly active tab's content is attached

#### Scenario: toggle off
- **WHEN** the toggle is off
- **THEN** messages are sent without page context (plain conversation)

#### Scenario: stays local and bounded
- **WHEN** context is attached
- **THEN** the page text is sent only to the local Ollama daemon and is capped to a bounded size
