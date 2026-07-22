# Tasks: tab-rename-and-ad-cosmetics

- [x] `BrowserTab.customTitle` + `displayTitle`; sidebar rows/chips/tooltip use `displayTitle`
- [x] Rename… / Reset Name context-menu items + handlers (promptForText)
- [x] Persist `SavedTab.customTitle`; restore + carry on tab recreate
- [x] Pinned/favourite tabs reopen at pin: `unload()` → `homeURL`; `saved()` persists `homeURL`
- [x] `AdCosmetics.script()` — hide `.adthrive-ad` + Google ad slots; inject under `blockAds`; Proton exempt
- [x] Verified live (rename, pin-reopen, swgoh.gg white footer gone); 86 XCTests green
- [x] Version bump → v0.24.0
