# Proposal: profiles

## Why

Arc Profiles — separate work / personal browsing. Each profile is its own isolated session:
cookies/logins, storage, cache, **and history/suggestions**, so signing into Facebook (etc.)
in one profile is independent of another, and search recommendations don't leak across them.

## What Changes

- **`Profile`** model (id, name, colour) persisted in `SidebarState.profiles`. Each **Workspace
  belongs to a profile** (`Workspace.profileId`; nil → the default profile).
- **Isolated cookie jar:** a persistent `WKWebsiteDataStore(forIdentifier:)` per profile; the
  **default** profile keeps the shared `.default()` store so existing logins survive. Tabs are
  created with their workspace's profile data store (`InjectionCoordinator`/`BrowserTab` accept
  a data store).
- **Isolated history:** a `HistoryStore` per profile (`history-<id>.json`; default keeps
  `history.json`). Recording, address-bar autocomplete, new-tab suggestions, and the command bar
  all use the **active workspace's profile's** history.
- **UI:** workspace context menu → **Profile ▸** (assign to a profile, or **New Profile…**).
  Assigning re-creates the workspace's tabs in the new jar (regular reload; pinned/favourite stay
  lazy).

## Impact

`Profile` + `Workspace.profileId` + `SidebarState.profiles`; `InjectionCoordinator`/`BrowserTab`
data-store param; `AppShell` gains per-profile data stores + per-profile history + the
workspace→profile assignment UI and tab re-creation. History from the shim host is unaffected
(parked auth-fork).
