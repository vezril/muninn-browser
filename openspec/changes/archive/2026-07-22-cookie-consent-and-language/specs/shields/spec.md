# shields

## ADDED Requirements

### Requirement: Block cookie-consent notices
Shields SHALL, when enabled (default on), dismiss website cookie-consent banners in a
privacy-preserving way — clicking "reject / necessary-only" (never "accept all") and hiding the
banner + unlocking scroll — across known consent platforms and, as a fallback, by clicking any
reject-labelled button (EN/FR) within a consent context. Globally toggleable; `*.proton.me` exempt.

#### Scenario: reject a known CMP banner
- **WHEN** a page shows a consent banner from a supported platform (OneTrust, Cookiebot, Didomi,
  AdThrive/Raptive, …)
- **THEN** the browser clicks its reject/necessary-only control and the banner is dismissed, without
  granting consent to non-essential cookies

#### Scenario: bilingual / unknown CMP
- **WHEN** a banner uses an unhardcoded platform or a bilingual label (e.g. "Déclin/Decline")
- **THEN** the reject button is still clicked via the language-agnostic text match, bounded to
  consent contexts

#### Scenario: never auto-accept
- **WHEN** a consent banner is handled
- **THEN** the browser never clicks "accept all"

#### Scenario: Proton exempt
- **WHEN** the page is on `*.proton.me`
- **THEN** the cookie-consent script does nothing
