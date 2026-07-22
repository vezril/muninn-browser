# Proposal: page-translation

**On-device page translation** — translate a foreign-language page into your preferred language, like
Chrome/Edge do, but **fully on-device**: no page text ever leaves the Mac.

## Why on-device

Chrome and Edge POST the page's text to Google/Microsoft translation servers. That's the opposite of
Muninn's privacy-first ethos. macOS ships Apple's `Translation` framework (on-device neural models,
macOS 15+), so Muninn translates locally — no cloud API, no account, no shim.

## What it does

An on-demand **Translate Page** action (toolbar button in the nav cluster, **File → Translate Page**,
and the ⌘N palette command "Translate Page"):

1. **Extract** — `PageTranslationScript.extract` walks the main frame's text nodes (skipping
   script/style/code/editable/hidden and letter-free nodes), capturing each node by *reference* in
   `window.__mtr` and returning `[{id, text}]`.
2. **Detect** — `NLLanguageRecognizer` finds the page's dominant language from a sample. If it already
   matches the target, a toast says so and nothing changes.
3. **Translate** — `PageTranslator` drives Apple's `TranslationSession` (batched, chunked at 64) into
   the target language. First use of a language pair triggers Apple's own on-device model-download UI.
4. **Reinject** — translated strings are written back by index; `window.__mtrTranslated` is set.

The button then shows a **filled** state / "Show Original" — clicking again reverts instantly from the
cached originals (`PageTranslationScript.revert`). State lives in the page, so it resets on navigation.

**Target language** reuses the existing `AppSettings.websiteLanguage` (default English) — the same
setting that drives Accept-Language — so there's no new preference to manage.

## Architecture note (SwiftUI bridge)

`TranslationSession` is only vended through the SwiftUI `.translationTask` modifier, so `PageTranslator`
hosts a 1×1 invisible `NSHostingView` in the window and drives it from the AppKit shell. The actual
`session.translations(from:)` calls run in a `nonisolated` helper so only Sendable `[String]` values
cross the MainActor boundary (`@preconcurrency import Translation` covers the non-Sendable session type).

## Scope / caveats (MVP)

- **Main frame only.** Cross-origin iframes have separate JS contexts; not translated in this cut.
- **Static snapshot.** Heavy SPAs that re-render after translating need a re-translate (a Mutation
  observer for live re-translation is a future step).
- **On-demand**, not auto-detect-on-load (a Chrome-style "Translate this page?" infobar is a future
  step). Calvin chose on-demand.
- Language availability is checked (`LanguageAvailability`); an unsupported pair surfaces a clear toast.

## Impact

New `Muninn/Translation/PageTranslator.swift` + `PageTranslationScript.swift`. `AppShell` gains a
`translateButton`, `translateActivePage`/`revertActivePage`/`updateTranslateIcon`, and a palette
command; `AppDelegate` gains a File-menu item. No new preferences. 86 XCTests green (no logic is
JS-side testable; the framework path is verified at the live gate).
