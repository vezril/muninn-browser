# Proposal: extension-popup-fixes

Fixes to extension action popups, from a deep investigation into why the Proton Pass popup rendered
blank. (Root cause for Proton Pass turned out to be its background — see below — but the investigation
surfaced two real, general popup bugs worth fixing.)

## Popups no longer collapse to blank

Some extension popups (async/React-rendered) size themselves to the viewport. WebKit initially
reports the popup viewport as ~1×1, so those popups lay out at 1×1 and render blank even though the
DOM mounted. The `presentActionPopup` delegate now detects a collapsed popup (`innerWidth <= 1`) and
injects a default document size so WebKit re-measures and the popup renders. Popups that size
themselves correctly are left untouched.

## Popups are transient/closable

Extension popovers are now `.transient` (dismiss on click-outside / Esc) and get a sensible default
content size when WebKit reports none. Previously a popup could open and not be dismissable.

## Extension contexts are inspectable

`WKWebExtensionContext.isInspectable = true` on load, so an extension's popup and background can be
attached to the Web Inspector for debugging (distinct from `WKWebView.isInspectable`).

## Proton Pass — resolved as "keep on the shim"

The investigation (via the WebKit specialist + live `context.errors` / `loadBackgroundContent`
probing) proved the blank Proton Pass popup is **not** a popup/API/sizing bug: its **MV3 background
service worker never finishes loading** (`loadBackgroundContent` never completes; the sample
extension's background loads instantly). The popup blanks because it waits on a background that
never starts. This matches ADR-005: Proton's `background.js` only boots in the custom DedicatedWorker
substrate the **shim** builds for it (it uses `importScripts` + heavy init). The generic
`WKWebExtension` MV3 runtime doesn't bring it up. Decision (Calvin): **Proton Pass stays on the
dedicated shim** (its purpose); the generic extension engine serves other extensions (content
scripts, popups, and background service workers all work — verified with the sample).

## Impact

`ExtensionBridge.presentActionPopup` (collapse fix), `AppShell.extPresentActionPopover` (transient +
default size), `ExtensionManager.load` (isInspectable). Diagnostics removed. 86 XCTests green.
