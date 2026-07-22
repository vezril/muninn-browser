# Proposal: shields

## Why

A privacy-first browser should block ads/trackers and harden connections by default —
Brave-Shields-style, per-site controllable. WKWebView supports this cleanly via
`WKContentRuleList` (+ a per-navigation JS preference).

## What (scoped with Calvin)

Four protections, on by default, each per-site controllable:

- **Block ads & trackers** — `WKContentRuleList` from a bundled blocklist (~120 common ad/tracker
  hosts), blocking third-party requests. (Full EasyList import is a later step.)
- **Upgrade connections to HTTPS** — `make-https` rules.
- **Block cross-site cookies** — `block-cookies` on third-party requests.
- **Block scripts (per-site)** — `WKWebpagePreferences.allowsContentJavaScript` per navigation.

**Shield UI:** a shield button on the address row → a per-site popover with a master
Shields on/off toggle, a per-site "Block scripts" toggle, and a **status readout** of active
protections (no block *count* — WKWebView can't count blocks precisely; Calvin chose status-only).
Global on/off for each protection in **Settings → Shields**. Turning Shields down for a site adds
an `ignore-previous-rules` exemption. State persists.

## Impact

New `ShieldsManager` (settings, per-site state, blocklist, rule compile/apply), `ShieldsPanel`
popover, a Settings → Shields section, and a shield button in `AppShell`. `InjectionCoordinator`'s
`decidePolicyFor` moves to the **preferences variant** to set `allowsContentJavaScript` (Peek's
`onNavigationAction` preserved). Rule list is applied to every tab and recompiled on change.

## Out of scope (not feasible in WKWebView)

Precise block counts, fingerprinting defense, phishing/malware alerts, CNAME uncloaking,
resource-replacement — these need a custom network stack.
