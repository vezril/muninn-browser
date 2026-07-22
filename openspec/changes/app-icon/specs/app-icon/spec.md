# app-icon

## ADDED Requirements

### Requirement: Muninn has an app icon
The app SHALL ship a raven app icon via the asset catalog, at all macOS sizes, appearing in the
Dock and Finder.

#### Scenario: icon shows
- **WHEN** the app is built and run
- **THEN** the Dock/Finder show the raven-on-navy squircle icon (not the generic default)

### Requirement: The landing page shows a faint icon-raven watermark
The new-tab landing page SHALL display a faint watermark of the same icon raven, behind the
content, tinted to the light/dark theme.

#### Scenario: watermark behind content
- **WHEN** a new tab opens
- **THEN** a subtle raven silhouette (matching the app icon) sits behind the title and search box
  without obscuring them, and adapts to light/dark
