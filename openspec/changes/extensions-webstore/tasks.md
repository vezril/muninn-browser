# Tasks: extensions-webstore

- [x] `ExtensionManager.addFromWebStore` — id parse → CRX download → strip → unpack/load
- [x] `extensionID(from:)` + `zipData(fromCRX:)` (CRX2/3 header stripping)
- [x] Settings → Extensions inline install row (paste-friendly) + "Add Unpacked / .zip / .crx…"
- [x] Move extension action icons to the address row (fix narrow-sidebar clipping/unclickable)
- [x] Hermetic ExtensionManager under XCTest (S2 tests independent of installed extensions)
- [x] 5 unit tests (id parsing + CRX strip); validated live against a real store CRX
- [x] 86 XCTests green
- [x] Version bump → v0.22.0
