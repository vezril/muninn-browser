# frame-registry Specification

## Purpose
TBD - created by archiving change e5-injection-frame-registry. Update Purpose after archive.
## Requirements
### Requirement: Frame registry answers webNavigation frame queries
The shim SHALL maintain a frame registry from `WKNavigationDelegate`/`WKFrameInfo` sufficient to answer `webNavigation.getFrame` and `webNavigation.getAllFrames`, assigning the main frame id `0` (Chrome convention) and stable integer ids to subframes.

#### Scenario: getAllFrames on a multi-frame page
- **WHEN** a page with nested iframes is loaded and `webNavigation.getAllFrames` is called
- **THEN** the returned set includes the main frame (id 0) and each subframe with a distinct id and its URL

#### Scenario: getFrame by id
- **WHEN** `webNavigation.getFrame({frameId})` is called for a known frame
- **THEN** the frame's details (id, url, parentFrameId) are returned; an unknown id returns null

### Requirement: runtime.getFrameId resolves the caller's frame
`runtime.getFrameId` SHALL return the frame id of the content-script context that called it, resolved from the calling `WKScriptMessage`'s `frameInfo` (the one genuinely-new API from E1's re-grep, Tier-2).

#### Scenario: getFrameId from a content script
- **WHEN** `orchestrator.js` (or a test content script) in the main frame calls `runtime.getFrameId(0)` / the current-frame form
- **THEN** it receives the main frame's id (0); the same call from a subframe returns that subframe's id

