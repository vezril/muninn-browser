# browser-shell

## ADDED Requirements

### Requirement: Apple Reminders integration
Muninn SHALL integrate with Apple Reminders on-device (EventKit), providing a sidebar tool to view and
manage reminders and lists, and commands to create reminders and lists — including from the current page.

#### Scenario: view and manage reminders in the sidebar
- **WHEN** the user opens the Reminders tool and grants access
- **THEN** the selected list's reminders are shown, and the user can complete, edit, delete, and add
  reminders, switch lists, and create a new list

#### Scenario: reminder from the current page
- **WHEN** the user invokes "New Reminder from Page"
- **THEN** a reminder capturing the page's title and URL is added to the default list

#### Scenario: list from the current page
- **WHEN** the user invokes "Create Reminders List from Page" on a page with recognizable list content
  (e.g. a recipe)
- **THEN** a new list is created and populated from the page's structured recipe data, or from a local
  model when no structured data is present, and the tool is shown focused on the new list

#### Scenario: access declined
- **WHEN** Reminders access has not been granted
- **THEN** the user is told how to enable it and no reminders are shown
