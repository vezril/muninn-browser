# Proposal: previews

## Why

Arc's "Previews — Glance Top Sites": hover a favourite (top site) to see a live preview of it
without opening it, so you can glance/triage (e.g. check inbox/calendar) at a glance.

## What Changes

- **Hover a favourite icon** (top of the sidebar) for ~0.5s → a **live preview popover** of that
  site opens beside the icon (480×560), anchored with an arrow.
- The preview is a real, **interactive** WKWebView carrying the Pass shim on the **shared**
  background host / data store (shared cookies → logged-in sites show your session).
- **Dismiss:** moving the cursor off both the icon and the popover closes it after a short
  grace; hovering into the popover keeps it open. Clicking the favourite still opens it fully.
- One reused preview web view, blanked (`about:blank`) on close to free the page.

## Impact

`AppShell` gains a hover-preview manager (`NSPopover` + a reused `InjectionCoordinator`) and
wires favourite-icon `onHover`. No model/persistence changes.
