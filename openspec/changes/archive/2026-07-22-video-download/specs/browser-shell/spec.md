# browser-shell

## ADDED Requirements

### Requirement: Video download
Muninn SHALL let the user download the video on the current page (best video, or audio-only) on supported
video sites, showing progress and recording the result in the Library, using an external downloader
(yt-dlp/ffmpeg) when available.

#### Scenario: download a video
- **WHEN** the user activates the download-video control on a supported video site
- **THEN** the page's video downloads to the profile's download folder, with progress shown, and is
  recorded in the Library on completion

#### Scenario: audio only
- **WHEN** the user chooses the audio-only option
- **THEN** the audio is downloaded as an MP3

#### Scenario: downloader unavailable
- **WHEN** the external downloader is not installed
- **THEN** the control is hidden and the user is told what to install

### Requirement: Library item actions
Muninn SHALL provide a right-click menu on Library items with Open, Show in Finder, Copy Path, Move to
Trash (recoverable), and Remove from List.

#### Scenario: reveal a download
- **WHEN** the user right-clicks a download and chooses Show in Finder
- **THEN** the file is revealed in Finder

### Requirement: Toolbar control reliability
The nav toolbar controls SHALL remain fully clickable at every allowed sidebar width, and the settings
control SHALL open the Settings window.

#### Scenario: settings at a narrow sidebar
- **WHEN** the sidebar is at its minimum width and the user clicks the settings control
- **THEN** the whole control is clickable and the Settings window opens
