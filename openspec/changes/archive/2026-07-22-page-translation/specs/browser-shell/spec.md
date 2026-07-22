# browser-shell

## ADDED Requirements

### Requirement: On-device page translation
Muninn SHALL provide an on-demand action to translate the active page's main-frame text into the
user's preferred website language using an on-device translation engine, such that no page content
leaves the device, with the ability to restore the original text.

#### Scenario: translate a foreign-language page
- **WHEN** the user invokes Translate Page on a page whose detected language differs from the preferred
  website language
- **THEN** the page's visible text is translated in place into the preferred language, entirely on-device

#### Scenario: already in the target language
- **WHEN** the user invokes Translate Page on a page already in the preferred language
- **THEN** the page is left unchanged and the user is told it is already in that language

#### Scenario: restore original
- **WHEN** the user invokes the action again on a translated page
- **THEN** the original text is restored from the cached originals

#### Scenario: unsupported language
- **WHEN** translation for the page's language is not available on the device
- **THEN** the user is informed and the page is left unchanged
