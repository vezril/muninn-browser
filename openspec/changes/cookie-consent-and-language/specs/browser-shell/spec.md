# browser-shell

## ADDED Requirements

### Requirement: Preferred website language
Muninn SHALL let the user choose the language websites detect (default English), applied via the
`Accept-Language` header and by overriding `navigator.language`/`navigator.languages`, so a foreign
IP/locale doesn't change the site language.

#### Scenario: default English
- **WHEN** the user has not changed the setting
- **THEN** websites see English (`Accept-Language` en + `navigator.language` en-US)

#### Scenario: change language
- **WHEN** the user picks a language in Settings → General
- **THEN** new tabs' `navigator.language` reflects it immediately, and the `Accept-Language` header
  reflects it after the next launch

#### Scenario: IP-based content unaffected
- **WHEN** a site serves a language by IP geolocation for legal compliance (not browser language)
- **THEN** that content is not changed by this setting
