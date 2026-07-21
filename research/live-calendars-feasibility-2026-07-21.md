# Live Calendars (Proton) — feasibility (2026-07-21)

Analysis behind the `live-calendars` OpenSpec change. Question: can Muninn do Arc's
"Live Calendars" but for **Proton Calendar**?

## What Arc's feature is

Pin Google Calendar → its favicon shows a **countdown to your next event**; near start time a
**Join** button appears that one-click-opens the Zoom/Google Meet call. Reminder lead time is
configurable. Arc's data comes from **Google Calendar's OAuth API** (a supported server feed of
next-event + conferencing link).
- https://resources.arc.net/hc/en-us/articles/24158102740631-Live-Calendars (help)
- https://techcrunch.com/2024/06/14/arc-browser-new-live-calendar-button-feature

## The core obstacle for Proton

Proton Calendar is **end-to-end encrypted** and exposes **no public API, no OAuth, no CalDAV** —
servers hold only ciphertext; decryption is on-device with keys unlocked at login. So Arc's clean
API path is unavailable.
- https://blog.mailfence.com/proton-calendar-support-caldav/
- https://proton.me/blog/protoncalendar-security-model

## Data-source options

- **A. Official API/OAuth** (Arc's Google path) — **does not exist for Proton.** Ruled out.
- **B. ICS share-link feed** ⭐ — Proton lets the user create a **read-only share link** that is a
  genuine downloadable/subscribable `.ics`; Muninn fetches + parses it locally. Credential-free,
  privacy-preserving, low maintenance. Cost: not real-time (poll + Proton's refresh cadence),
  needs one-time user setup, read-only.
  - https://proton.me/support/share-calendar-via-link
- **C. DOM-scrape a logged-in Proton Calendar** in a hidden web view — read the already-decrypted
  next event from Proton's own SPA. Near-real-time, no setup beyond being logged in, but **fragile**
  against Proton UI changes.
- **D. Reimplement Proton's internal calendar API + PGP decryption** via the native fetch proxy —
  real-time and "native," but large crypto/protocol effort against an unversioned internal API.

## Rendering side — already mostly built

Muninn has favourite tiles, live hover previews (web view on the profile session), timers, and
`openRouted`/`openInNewTab`. A countdown + Join surface is ordinary AppKit work, and Join composes
with Air Traffic Control. The UI is the cheap half.

## Verdict

Feasible. The UI is easy; the gate is data access, and since Proton has no API the realistic MVP is
**Option B** (ICS share link) — chosen for the `live-calendars` change — architected behind a small
interface so the source can later swap to C/D for freshness. Display surface: a new **right-side
Tools sidebar** (Calvin's call, 2026-07-21) rather than a left-tile badge. Recurrence: **full
RFC 5545** (recurring meetings are the point), covered by a pure, fixture-tested parser.
