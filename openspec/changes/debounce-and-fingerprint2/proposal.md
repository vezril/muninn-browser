# Proposal: debounce-and-fingerprint2

Two additions to the Shields suite, from a read-through of Brave's privacy updates (debouncing #11,
fingerprinting 2.0 #4, language #17). The rest were assessed as already-in-WebKit (ephemeral
storage #7, network-state partitioning #14) or not feasible in WKWebView (Pool-Party #13,
unlinkable bouncing #16).

## Debouncing (bounce-tracking protection)

- **`Debouncer`** (pure, tested): if a navigation targets a known bounce-tracker that carries the
  real destination in a query param (`l.facebook.com?u=`, `out.reddit.com?url=`, `vk.com/away.php?to=`,
  Outlook SafeLinks, Steam linkfilter, `google.com/url`, …), recover the destination and skip the
  tracker. Curated host[+path]→param rule list.
- Applied in `AppShell.decideNavigation` before query-stripping (chained bounces resolve; the
  destination is then query-stripped). Gated by `ShieldsManager.debounce` (default on) + per-site
  Shields. Settings → Shields toggle + panel row.

## Fingerprinting 2.0 (+ language)

Upgrades the farbling script:

- **Per-session, per-site seed** = `hash(sessionToken + eTLD+1)` (`ShieldsManager.sessionToken`, a
  per-launch UUID) — values consistent within a session for a site, different across sites/sessions.
- **More surfaces**: `measureText`, standardized `hardwareConcurrency`, and reduced language entropy
  (`navigator.languages` → primary only) — on top of the existing canvas/WebGL/audio.
- `*.proton.me` still exempt.

## Impact

New `Debouncer` + `debounce`/`sessionToken` on `ShieldsManager`; `FingerprintDefense.script` now
takes the token; `decideNavigation` debounces; Settings + panel gain a row. 4 debouncer tests.
