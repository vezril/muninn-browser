# Proposal: cookie-consent-and-language

Two daily-driver privacy/QoL additions.

## Cookie-consent notice blocking (Shields)

A new Shields protection (`blockCookieNotices`, default on): `CookieConsent.script()` — injected
MAIN-world, document-start, all frames — that **auto-clicks "reject / necessary-only"** on known
consent-management platforms and hides the banner + unlocks scrolling. **Never** clicks "accept all"
— no interaction means no consent, so sites fall back to essential-only cookies (privacy-preserving,
per the decline-non-essential default).

Coverage:
- **Curated CMP selectors** — OneTrust, Cookiebot, Didomi, Usercentrics, Quantcast, TrustArc, Osano,
  Complianz, Sourcepoint, and **AdThrive/Raptive** (`.adthrive-act25-*`, US-CMP, CCPA — the Quebec
  Law 25 modal that prompted this).
- **Language-agnostic text reject** — clicks buttons whose label contains a strong reject phrase
  (EN + FR: "reject all", "decline", "refuser", "tout refuser", "continuer sans accepter",
  "nécessaires uniquement", …), bounded to frames whose text mentions cookies/consent so it never
  clicks an unrelated button. Handles bilingual labels like "Déclin/Decline".
- **Cross-origin iframe CMPs** — hides consent iframes (AdThrive, Sourcepoint) from the parent.
- **MutationObserver** (childList + `class`/`style` attributes, ~20s) — catches banners injected
  late or shown by toggling a `.show` class.
- `*.proton.me` self-exempts (keeps the shim/auth-fork path pristine).

Toggle in Settings → Shields + the shield popover status.

## Preferred website language (default English)

Websites previously saw the system locale (a Quebec IP/locale → French). Now:
- `AppSettings.websiteLanguage` (default `"en"`) sets `AppleLanguages` at launch → the WKWebView
  **`Accept-Language`** header for all requests.
- An injected document-start script overrides **`navigator.language` / `navigator.languages`** (what
  SPAs like Proton read) — immediate, applies to new tabs incl. proton.me.
- Picker in Settings → General ("Language websites see": English…System). The header fully applies
  after a restart; the `navigator` override applies to new tabs immediately.

Note: this changes the language sites detect from the *browser*. It cannot override banners a site
serves by **IP geolocation** for legal compliance (e.g. Quebec Law 25 French consent text) — that's
tied to location, not browser language.

## Impact

New `CookieConsent` + `ShieldsManager.blockCookieNotices`; `AppSettings.websiteLanguage` +
`applyWebLanguageAtLaunch`; `InjectionCoordinator` injects both scripts (language override before
fingerprint defense); Settings gains a Shields toggle + a General language picker; shield popover
gains a status row. 86 XCTests green.
