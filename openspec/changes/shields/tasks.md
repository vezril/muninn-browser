# Tasks: shields

- [x] `ShieldsManager`: global settings, per-site state (shields-down / scripts), bundled blocklist, rule JSON, compile + apply
- [x] Rule list applied to every tab; recompiled + re-applied on change; per-site `ignore-previous-rules` exemption
- [x] Per-site JS blocking via `InjectionCoordinator` preferences `decidePolicyFor` (Peek preserved)
- [x] `ShieldsPanel` popover (master toggle, block-scripts, status readout, settings link) + shield button in the address row (icon reflects up/down)
- [x] Settings → Shields section (global toggles)
- [x] Live-verified (Calvin): blocking, HTTPS upgrade, per-site shields off/on, script block
- [ ] Ship: full suite green; version bump + tag; archive
