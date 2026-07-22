# Tasks: extension-popup-fixes

- [x] Fix async/self-sizing popups collapsing to 1×1 (force default size when viewport <= 1px)
- [x] Make extension popovers transient (click-outside / Esc dismiss) + default size when WebKit gives none
- [x] Mark extension contexts inspectable (WKWebExtensionContext.isInspectable)
- [x] Investigate Proton Pass blank popup → root cause: MV3 background SW never starts; keep on shim
- [x] Remove all diagnostics; 86 XCTests green
- [x] Version bump → v0.22.1
