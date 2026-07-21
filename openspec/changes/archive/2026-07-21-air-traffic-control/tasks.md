# Tasks: air-traffic-control

## Model + persistence
- [x] Add `RoutingRule` (`id`, `host`, `workspaceId`) with suffix-aware `matches(_:)`
- [x] Add `routingRules` to `SidebarState`; load/save in `AppShell` + `persist()`

## Routing chokepoint
- [x] Add `openRouted(_:newTab:)` to `AppShell` (switch space + open, else load/new-tab)
- [x] Route the address bar: `navigate` → `openRouted(url, newTab: false)`
- [x] Route the command tool: `CommandPalette` `.url` → `openRouted(url, newTab: true)`
- [x] Route external links: `AppDelegate.application(_:open:)` + launch flush → `route`,
      which routes or falls back to Quick Look

## Settings → Routing
- [x] Add "Routing" nav item (5th) to `SettingsWindowController`
- [x] Rule list UI: host field + space picker + remove; "Add Rule" button; empty state
- [x] `AppShell` settings API: `settingsRoutingRules`, `settingsWorkspacePicker`,
      `settingsAddRule`, `settingsRemoveRule`, `settingsUpdateRule`

## Verify
- [x] Build clean; 42 XCTests green
- [x] Live-verified by Calvin: external link, address bar, and command tool all route
