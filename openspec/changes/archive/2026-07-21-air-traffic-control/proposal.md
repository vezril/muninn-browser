# Proposal: air-traffic-control

## Why

Muninn's workspaces each carry their own profile (isolated cookie/login jar) and their
own favourites/pins/tabs. When a link arrives — from another app (Muninn as default
browser), from the address bar, or from the command tool — it always lands in the *active*
space, regardless of which space that site belongs to. A work Slack link opened while
you're in your Personal space ends up in Personal (wrong profile, wrong session). Arc's
"Air Traffic Control" solves this by letting you bind a host to a space so its links
always open there.

## What

A user-configurable set of **routing rules** (`host → workspace`). Whenever a URL is
opened through a user-facing entry point, if a rule matches the URL's host and points at a
*different* space than the active one, Muninn switches to that space (which switches its
profile) and opens the URL in a new tab there. No match → normal behaviour (load in place,
or a Quick Look for an external link).

Rules are managed in a new **Settings → Routing** section: a list of `host → space`
rows with an add button, an editable host field, a space picker, and a remove button.
Rules persist in `sidebar.json`.

## Scope (this change)

- `RoutingRule` model (`host`, `workspaceId`) with suffix-aware host matching
  (`github.com` also matches `gist.github.com`), persisted in `SidebarState.routingRules`.
- A single routing chokepoint, `openRouted(_:newTab:)`, honoured by all three URL entry
  points: external links (`AppDelegate.application(_:open:)` → `route`), the address bar
  (`navigate`), and the command tool (`CommandPalette` `.url`).
- Settings → Routing UI (5th nav item) with full CRUD.

**Deferred:** path/wildcard matching (host-only for now), per-rule "open in current tab vs
new tab", auto-suggesting rules from browsing history.

## Impact

New `RoutingRule` type; `SidebarState` gains `routingRules`. `AppShell` gains `route`,
`openRouted`, and the routing settings API; `navigate` and the command palette's `.url`
open route through `openRouted`. `SettingsWindowController` gains the Routing section.
External-link handling changes from "always Quick Look" to "route, else Quick Look".
No shim/background changes. 42 XCTests remain green.
