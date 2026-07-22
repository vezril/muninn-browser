# Proposal: extensions-webstore

Extend the browser-extensions feature with **Chrome Web Store install**, plus two fixes surfaced
while testing it.

## Web Store install

- Settings → Extensions gains an **inline** install row: paste a Chrome Web Store link (or a bare
  32-character extension id) and press **Install** (or Return). Inline in the pane — not an NSAlert
  accessory field, which is unreliable for paste/select-all.
- `ExtensionManager.addFromWebStore(_:)`: parse the 32-char id (`extensionID(from:)`), download the
  CRX from Google's on-demand endpoint (`clients2.google.com/service/update2/crx`), strip the CRX2/3
  header down to the embedded ZIP (`zipData(fromCRX:)`), then run it through the existing
  unpack/load path. Validated end to end against a real store CRX (uBlock Origin Lite).
- The folder/.zip/.crx picker remains as "Add Unpacked / .zip / .crx…".

## Fix: extension icons clipped on a narrow sidebar

The extension action buttons lived in the top-bar cluster, which (offset past the traffic lights) is
too narrow to hold a variable number of icons — at the minimum sidebar width they rendered past the
right edge, clipped, and were **unclickable**. Moved the extension action icons to the **address
row** (left of the Share button, full width, no traffic-light offset) so they're always visible and
clickable. Shield + settings stay in the top cluster.

## Fix: hermetic ExtensionManager under test

The S2 clean-world tests read the developer's *real* installed extensions from Application Support;
once an extension is enabled the controller attaches and `browser` appears in the page MAIN world,
failing the tests. `ExtensionManager` now loads no installed extensions under XCTest
(`XCTestConfigurationFilePath`), keeping the suite hermetic.

## Compatibility note

A store extension may download and load yet not fully run — WKWebExtension implements Apple's
WebExtensions subset. In particular **Proton Pass** installs and its popup opens but renders empty:
its popup depends on the background + account-app login handshake that this project's dedicated
Proton Pass shim provides, not the generic extension runtime. This is a known limitation, not a bug;
a simple extension (e.g. the bundled sample) exercises the full content-script + popup path.

## Impact

`ExtensionManager` gains `addFromWebStore`/`extensionID`/`zipData` + a test guard; Settings gets the
inline install row; `AppShell` moves the extension toolbar to the address row. 5 new unit tests
(id parsing + CRX strip); 86 XCTests green.
