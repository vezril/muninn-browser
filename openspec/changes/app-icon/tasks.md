# Tasks: app-icon

- [x] Process the generated art into the macOS rounded tile (mask crops the sparkle + native corners)
- [x] Slice all sizes (16→1024, @1x/@2x) into `Assets.xcassets/AppIcon.appiconset` + Contents.json
- [x] Wire `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`; verify `CFBundleIconName`/`Assets.car` in the build
- [x] Extract the icon raven as a silhouette (by saturation) → `ravenMaskDataURI`
- [x] Landing page `.raven-bg` faint theme-tinted CSS mask watermark
- [x] Live-verified (Calvin): icon in Dock, watermark on new tab
- [ ] Ship: full suite green; version bump + tag; archive
