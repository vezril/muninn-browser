# minimal-shell Specification

## Purpose
TBD - created by archiving change e6-auth-fork-login. Update Purpose after archive.
## Requirements
### Requirement: Single navigable window and tab
Muninn SHALL present one `NSWindow` containing one tab backed by a `WKWebView` (system WebKit only, FR-4), with an address field and back/forward/reload controls, sufficient to navigate to an entered URL (FR-1, FR-5). This is the minimal shell — no multi-tab model, session restore, or downloads (those are E9).

#### Scenario: Navigate to a URL
- **WHEN** Calvin enters `https://account.proton.me` (and later an arbitrary site URL) in the address field and submits
- **THEN** the tab's WKWebView loads that page, the address field reflects the committed URL, and back/forward/reload operate on the navigation stack

#### Scenario: WebKit-only rendering
- **WHEN** the shipped app is inspected
- **THEN** all web content renders via `WKWebView`; no other engine is linked (FR-4)

#### Scenario: GUI launch is human-gated
- **WHEN** the app (which opens a visible window) is about to be launched during development/validation
- **THEN** Calvin is warned in chat and the launch waits for his confirmation (ground rule 2)

