# Tasks: profiles

## 1. Model + data store

- [x] 1.1 `Profile` model; `Workspace.profileId`; `SidebarState.profiles`; migrate a default "Personal" profile.
- [x] 1.2 `InjectionCoordinator`/`BrowserTab` accept a `WKWebsiteDataStore`; per-profile persistent store (`forIdentifier:`), default profile → shared `.default()`.
- [x] 1.3 `makeTab(workspaceId:)` uses the workspace's profile store; restore assigns correct stores.

## 2. History isolation

- [x] 2.1 `HistoryStore(fileName:)`; per-profile stores; recording/autocomplete/suggestions/command-bar use the active profile's history.

## 3. UI

- [x] 3.1 Workspace context menu → Profile submenu (assign / New Profile…); assigning re-creates the workspace's tabs in the new jar.

## 4. Ship

- [x] 4.1 Full suite green; ship PR-gated; update `CLAUDE.md`; cut version.
