# media-controls

## ADDED Requirements

### Requirement: Pause all playing media across every tab
A single command SHALL pause every playing `<video>`/`<audio>` in all tabs across all workspaces,
including same-origin subframes, and report how many it paused.

#### Scenario: videos playing in several tabs
- **WHEN** the user invokes Pause All Videos (⌘⇧P, File menu, or the command palette)
- **THEN** every playing video/audio pauses and a toast reports the count

#### Scenario: nothing is playing
- **WHEN** no tab is playing media
- **THEN** nothing changes and the toast says so (no silent no-op)

### Requirement: Mute every tab, including tabs opened later
A single command SHALL toggle a whole-page mute on every tab — covering `<video>`, `<audio>`, and
Web Audio, and surviving the page starting new sound — and newly opened tabs SHALL inherit the
muted state while it is active.

#### Scenario: mute everything, then open a new tab
- **WHEN** the user invokes Mute All Tabs and afterwards opens a new tab that autoplays sound
- **THEN** the new tab is silent too

#### Scenario: unmute restores audio
- **WHEN** the user invokes the command again
- **THEN** every tab is unmuted

### Requirement: A tab playing sound shows a speaker control
A tab that is currently playing media SHALL show a speaker icon in its sidebar row, and clicking it
SHALL mute/unmute only that tab. The icon SHALL NOT appear for tabs that are not playing.

#### Scenario: indicator appears and toggles
- **WHEN** a tab starts playing a video and the user clicks its speaker icon
- **THEN** that tab (and only that tab) is muted, and the icon shows a slashed speaker

#### Scenario: indicator disappears when playback stops
- **WHEN** playback stops in that tab
- **THEN** the speaker icon is removed from its row
