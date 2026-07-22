# Proposal: shields-query-stripping

## Why

From Brave's privacy grab-bag (https://brave.com/privacy-updates/5-grab-bag/): tracking query
parameters (`fbclid`, `gclid`, `msclkid`, `utm_*`, …) let advertisers correlate you across sites.
This adds the one feature from that article that's a clean fit for WKWebView, to the Shields suite.

(The article's other two — referrer-policy tightening and Reporting-API removal — were assessed
and skipped: WebKit's referrer default is already `strict-origin-when-cross-origin`, and WebKit
doesn't ship the Chromium Reporting API, so there's nothing to remove.)

## What

- **`QueryStripper`** (pure): removes known tracking params (click IDs + `utm_`/`hsa_`/`oly_`
  prefixes + tokens) from a URL, keeping benign params. Unit-tested.
- Applied to main-frame navigations in `decideNavigation` (cancel → reload the cleaned URL, so
  history keeps the clean version), gated by Shields per-site and a global toggle. Peek preserved.
- **Settings → Shields** toggle "Strip tracking URL parameters" (default on) + a panel status row.

## Impact

New `QueryStripper` + a `stripQueryParams` flag on `ShieldsManager`; `AppShell.decideNavigation`
strips + `loadCleaned` re-loads; Settings + panel gain a row. No content-rule recompile (it's an
in-flight rewrite). 5 unit tests.
