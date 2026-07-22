# Proposal: share-link-cleaning

Strip tracker/attribution parameters from links **you hand to other people** — the share-time cousin of
the existing navigation-time `QueryStripper`.

## Why

Platforms append attribution tokens only when you copy/share a link — YouTube's `?si=`, TikTok's
`_t`/`_r`, X's `s`/`t`, Instagram's `igsh`, Amazon's `/ref=…`. These let the platform tie the recipient
back to you. `QueryStripper` (Shields) already removes global click-IDs/UTM during navigation, but these
share tokens are a distinct, per-platform class and are added at share time, so they need cleaning in the
copy/share paths.

## What it does

`ShareLinkCleaner.clean(_:)` (pure, unit-tested) cleans a URL for sharing:
- Removes the **global** cross-site trackers `QueryStripper` knows (utm_*, fbclid, gclid, …).
- Removes **host-scoped** share-attribution params from a curated per-platform ruleset — scoped because
  names like `si`/`t`/`s` are ambiguous, so meaningful params survive: YouTube `t` (timestamp) + `list`,
  Reddit `context`, Instagram `img_index`.
- Amazon-style path cleanup: truncates `/dp/<ASIN>/ref=…` → `/dp/<ASIN>`.

Platforms covered: YouTube, Spotify, Twitch, Bilibili, X/Twitter, Instagram, Facebook, TikTok, Reddit,
LinkedIn, Pinterest, Substack, Medium, Amazon (13 TLDs), eBay, AliExpress, Google, Steam. Adding one is a
single `Rule`.

Applied in every path that hands a link to someone else — **Copy Link** (⌘⇧C), **Copy as Markdown**
(⌘⇧⌥C), the **Share** button, and the copy toast's Share button — via a `shareURL()` helper. It **never**
alters the page being viewed. Gated by `ShieldsManager.cleanSharedLinks` (default on); toggle in
**Settings → Shields → "Strip trackers from copied & shared links."**

## Scope / caveats

- Query params + Amazon path only; fragment-based trackers and other path rewrites are out of scope.
- Curated (not the full ClearURLs database) — the platforms people actually share from. Extend by adding
  a `Rule`.

## Impact

New `Muninn/Shields/ShareLinkCleaner.swift` (reuses `QueryStripper` for the global set). `ShieldsManager`
gains `cleanSharedLinks`; `AppShell` gains `shareURL()` applied to the copy/markdown/share paths;
`SettingsWindowController` gains one toggle. 103 XCTests green (+11 `ShareLinkCleanerTests`, incl. the
`youtu.be/…?si=…` example); live-gated.
