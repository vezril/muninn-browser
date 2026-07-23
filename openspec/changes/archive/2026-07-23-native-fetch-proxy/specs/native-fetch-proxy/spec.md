# native-fetch-proxy

## ADDED Requirements

### Requirement: Extension worker fetches to host_permissions origins bypass CORS
The extension worker's `fetch` to a `host_permissions`-scoped origin SHALL be routed
through a native `URLSession` proxy and succeed despite the worker's custom-scheme origin
(which the browser CORS-blocks). Non-scoped and non-http(s) requests SHALL fall through to
the platform `fetch` unchanged.

#### Scenario: GET to the Proton API succeeds
- **WHEN** the worker does `fetch("https://pass.proton.me/api/…", {credentials:"include"})`
- **THEN** it resolves to a `Response` with the real `status`, headers, and body (not a
  `TypeError: Load failed`), and `.json()`/`.text()` work

#### Scenario: own extension resources are not proxied
- **WHEN** the worker fetches a `muninn-ext://<id>/…` resource (or a `blob:`/`data:` URL)
- **THEN** it is served by the platform `fetch`, not the native proxy

### Requirement: The proxy is deny-by-default and cannot become an open proxy
The proxy SHALL be reachable ONLY from the background host worker, and SHALL only issue
requests to an allowlist of `https` `*.proton.me` hosts, re-checking the allowlist across
redirects.

#### Scenario: a non-allowlisted host is refused
- **WHEN** a request targets a host that is not `proton.me` or a `*.proton.me` subdomain
  (including look-alikes like `evilproton.me`)
- **THEN** the proxy refuses it with a network error and makes no request

#### Scenario: a page cannot reach the proxy
- **WHEN** page/content-world JS attempts the `__fetch` broker call
- **THEN** it is not routed to the proxy (the `__fetch` route exists only on the host's
  `broker` handler, not the page's `brokerIsolated`)

#### Scenario: a redirect off the allowlist is stopped
- **WHEN** an allowlisted request receives a redirect to a non-allowlisted host
- **THEN** the proxy does not follow it

### Requirement: The proxy holds the extension's own cookie session
The proxy SHALL use a dedicated native cookie store for `credentials:"include"`, isolated
from `URLSession.shared` and from the WKWebView data stores, so the extension's Proton
session does not leak to or from browser tabs.

#### Scenario: Set-Cookie from a proxied response is retained for later requests
- **WHEN** an allowlisted response sets a cookie and a later allowlisted request is made
- **THEN** the later request carries that cookie (from the dedicated native jar), and no
  browser tab's cookies are involved
