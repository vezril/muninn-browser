# Proposal: app-icon

## Why

Muninn shipped with no app icon (default generic tile) and a bare landing page. It now has a
face: a raven (Muninn = Odin's raven of memory) on a deep-navy squircle.

## What

- **App icon.** A Gemini-generated raven-head-in-profile on an indigo→midnight squircle,
  processed into the macOS icon: masked to the standard rounded tile (which also cropped a stray
  corner sparkle and gives native rounded corners), sliced into all required sizes (16→1024,
  @1x/@2x) in `Assets.xcassets/AppIcon.appiconset`, wired via
  `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
- **Landing-page watermark.** The **same icon raven**, isolated as a silhouette (by saturation —
  the raven is neutral-grey against the saturated blue), applied as a faint, theme-tinted CSS
  mask behind the new-tab content (~5% light / ~7% dark), so it reads as the same bird.

## Impact

New `Muninn/Assets.xcassets` (icon set); `project.pbxproj` gains the app-icon build setting;
`AppShell.landingHTML` gains the `.raven-bg` mask + a `ravenMaskDataURI` (base64 silhouette).
No behavior changes. Source art kept out of the repo.

## Notes

- Tooling: ImageMagick for the tile mask, size slicing, and silhouette extraction; `iconutil`/
  `sips` available but not needed. The silhouette tints per theme via CSS `mask` + `background`.
