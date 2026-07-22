# Tasks: cookie-consent-and-language

- [x] `ShieldsManager.blockCookieNotices` toggle (default on)
- [x] `CookieConsent.script()` — curated CMP reject/hide + text-based reject (EN/FR) + iframe-CMP hide
- [x] AdThrive/Raptive Act25 (Quebec Law 25) + US-CMP + CCPA selectors; bilingual label match
- [x] MutationObserver watches childList + class/style (catches `.show` toggles); Proton exempt
- [x] Inject in `InjectionCoordinator`; Settings → Shields toggle + shield popover status row
- [x] `AppSettings.websiteLanguage` (default en) + `applyWebLanguageAtLaunch` (AppleLanguages)
- [x] navigator.language/languages override injected before fingerprint defense
- [x] Settings → General language picker + hint
- [x] Verified live: swgoh.gg AdThrive banner auto-dismissed; 86 XCTests green
- [x] Version bump → v0.23.0
