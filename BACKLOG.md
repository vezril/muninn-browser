# Muninn — Backlog

Explored-but-not-started ideas. This is a holding pen for thinking that's ripe enough to remember but
not yet a change. When one is picked up, it graduates into an OpenSpec change (`openspec new change …`)
and gets removed from here. Not a commitment or a priority order — just so nothing good gets lost.

The locked planning artifacts (`prd.md`, `roadmap.md`) are separate and authoritative for the original
milestones; this file is for the organic features that have grown past them.

---

## Self-update via GitHub (personal, multi-machine, no Apple Developer Program)

**Status:** explored 2026-07-22, design settled, not started.
**Itch:** Muninn should update itself across Calvin's several Macs — GitHub publishes the build, the app
pulls it — without paying $99/yr for the Apple Developer Program.

### Direction chosen
A personal **notify-and-one-click self-updater** (not silent; a surprise relaunch mid-browse loses the
session). Not Sparkle — Sparkle's value (EdDSA-signed appcast + notarization) presumes public
distribution and a Developer ID. For a single owner, own repo, own machines, a lighter mechanism is
acceptable.

### Mechanism
```
ship flow (local):  build RELEASE → zip → gh release upload Muninn-x.y.z.zip
Muninn:  UpdateChecker → GitHub Releases API (releases/latest) → compare tag vs bundle version
         → toast "vX.Y.Z ready — Update & Relaunch"  (user picks the moment)
         → download zip → strip com.apple.quarantine → verify TeamID == XTH7663SR9
         → detached helper: wait for quit → cp -R over /Applications/Muninn.app → open
```

### Why this works for free, multi-machine (facts verified against the real bundle 2026-07-22)
- **No embedded provisioning profile** → the signature isn't device-locked; a dev-signed build's
  signature validates on any Mac (chains to Apple roots). The only gate on a second Mac is Gatekeeper
  **quarantine**, which the updater is allowed to strip on your own machines.
- **Stripping quarantine is sufficient.** Gatekeeper only enforces on quarantined files; `xattr -dr
  com.apple.quarantine` → the app launches with no prompt (same reason a locally-built copy runs). Holds
  on Sequoia (removing quarantine ≠ bypassing assessment).
- **FDA persists per machine.** The designated requirement is cert-based and stable, so an in-place
  bundle swap keeps each Mac's Full Disk Access grant.
- **Team-ID guardrail survives cert renewal.** Apple Development cert expires ~yearly, but Team ID
  **XTH7663SR9** stays constant — an updater that checks Team ID (not the cert) keeps working across
  renewals. (Cert rollover still costs a one-time FDA re-grant per machine when it happens.)

### Cost model (accepted)
- **Per new Mac, one-time:** download once → "Open Anyway" in Privacy & Security (un-notarized) → grant
  FDA. ~1 min. After that, updates are hands-free on that machine.
- **~Yearly:** re-sign when the dev cert rolls → one FDA re-grant per machine.
- The $99 Developer ID + notarization is exactly what would erase this front-loaded friction (no "Open
  Anyway", no quarantine strip, no yearly re-sign; certs last 5 yrs). Declined — the accepted friction
  is first-install, not ongoing.

### Scope when it graduates to a change
1. Switch the **published** artifact to a **Release** build (drop `get-task-allow`, ideally add hardened
   runtime) — today's ship flow builds Debug, which is debuggable and shouldn't run on multiple Macs
   holding a Proton session.
2. Fold `gh release upload Muninn-x.y.z.zip` into the existing ship flow so releases carry the artifact
   (today they're bare tags).
3. In-app `UpdateChecker`: poll GitHub Releases API, compare vs `MARKETING_VERSION`, surface via the
   existing toast/`NotificationStore`; a "Check for Updates…" menu item; a Settings toggle for cadence.
4. The updater: download → dequarantine → Team-ID verify → detached helper swap-and-relaunch (~30 lines;
   the one genuinely fiddly piece — can't overwrite a running bundle in place).

### Open decisions (defer to change time)
- Appcast/metadata source: GitHub Releases API `latest` (simplest) vs a hand-published `latest.json`.
- Where to host the check cadence (launch + periodic; interval in Settings).
- Whether to keep a "silent auto-install" toggle as a later add-on.

### Security note (be honest in the proposal)
Weaker than Sparkle: trust rests on HTTPS + GitHub + a Team-ID check, not a cryptographically signed
appcast. A compromised GitHub account could push a build, blunted (not eliminated) by the Team-ID check
since an attacker can't re-sign as XTH7663SR9 without the cert. Acceptable for personal use; revisit if
Muninn ever gains other users.

---

## Sync + Mobile (self-hosted "dumb relay" sync; iOS companion app)

**Status:** explored 2026-07-23, design settled on a direction, not started.
**Goal:** sync Muninn's setup across Calvin's devices — two MacBooks now, a **definitely-planned iOS app**
later (minimal features, not a full port) — in a way that's private and that Calvin owns.

### What actually syncs (triage — the payload is small)
Sync the **setup, not the session**. Muninn's state lives as JSON in `~/Library/Application Support/Muninn/`.
- **✅ sync:** `sidebar.json` (favourites, pins, folders, workspaces, profiles, routing rules, anchored
  tabs — the crown jewel) + a handful of **UserDefaults** prefs (search engine, shields, Obsidian/Pomodoro,
  shortcuts, calendars).
- **🟡 maybe:** `history-*.json` (autocomplete continuity; append-mostly, conflict-prone), `chat.json`.
- **❌ don't:** `downloads.json` (records point at machine-local file paths), `notifications.json`
  (ephemeral), `Extensions/`, `storage.key` / `storage.local.enc` (the Proton shim's secret+cache; Proton
  syncs itself), Reminders (already iCloud-synced via EventKit).

Net payload ≈ **one JSON file + some prefs** — exactly what a minimal iOS companion needs too.

### Chosen direction: a self-hosted, zero-knowledge record-log relay
Calvin is fine running a small server (NAS or cloud). That's the strongest fit — it's the always-on relay
pure P2P lacks, but one Calvin owns. **Keep the server dumb:** it understands nothing about Muninn.
```
  CLIENT (shared MuninnSync package, macOS+iOS): the smarts
    • record model (favourite/workspace/folder/setting) with stable id + updatedAt
    • merge rule (last-writer-wins per record/field; CRDT only if needed)
    • encrypts each record payload with a key from Calvin's passphrase (E2E)
                       │  opaque ciphertext + versions
                       ▼
  SERVER (NAS or cloud, one Docker container): dumb + zero-knowledge
    • table (userId, recordId, version, updatedAt, ciphertext) — can't read it
    • one endpoint:  POST /sync { sinceVersion, changed[] } → { changed[], newVersion }
    • storage: SQLite (one file); auth: per-device bearer token
```
**Why dumb wins:** tiny (a few hundred lines), never redeployed when the browser's model changes, and
E2E-encrypted so **cloud vs NAS are equivalent on privacy** (even a $5 VPS can't read the data). Polling
(launch + interval + on-edit push) is fine — no websockets needed day one. Stack: **Scala + Pekko HTTP**
is the natural fit (the roadmap already reserved Scala for the "sync/service layer", and it's in Calvin's
wheelhouse), but the design is stack-agnostic.

### Why not the alternatives (recorded so we don't re-litigate)
- **CloudKit:** lowest effort, free background push, private DB — but Apple-only, tied to iCloud, and not
  "owned." Viable fallback; the self-hosted relay wins on ethos + platform-openness (Android/web/Linux
  later). Its one real edge (free background push) is matchable with APNs (below).
- **Pure P2P / BitTorrent:** BitTorrent is the wrong shape (immutable content fan-out, no mutable-state
  merge). Real P2P (Syncthing, CRDT+libp2p) hits two hard walls: (1) **offline rendezvous** — two laptops
  rarely awake together + a sleeping phone never form a live mesh without an always-on node (= a server
  again); (2) **iOS kills background P2P** (no daemon/long-lived sockets — why there's no real Syncthing on
  iOS). A relay you own is the fix for both. See the 2026-07-23 explore thread for the full comparison.

### The two real wrinkles
1. **iOS background sync → APNs.** Server sends a silent push when data changes; iOS wakes Muninn to sync.
   APNs needs the $99 program — already required for iOS distribution anyway. Without it: foreground/launch
   sync (fine for a companion).
2. **NAS reachability (NAT).** Phone on cellular can't see a NAS behind home NAT. Fixes: **Tailscale**
   (private mesh, no port-forward, iOS app exists — most on-brand), Cloudflare Tunnel, or just a **cloud
   VPS** (always reachable; E2E means it's still zero-knowledge). Server URL becomes a setting → support
   either.

### The mobile app (minimal, not a port)
iOS mandates WebKit for all browsers, so there's no engine problem. v1 scope: **browse (WKWebView) + your
synced favourites/workspaces (a launcher) + reading-list / "send to phone" + Reminders (EventKit) +
Pomodoro.** OUT: the Proton Pass shim, extensions, split view, mini player, desktop chrome. The sync
payload it needs = the same durable "setup" core.

### First actionable step (independent of the $99 / server decision)
The durable investment isn't the transport — it's:
1. **Restructure the syncable state to record-level** — stable ids + `updatedAt` per favourite/workspace/
   folder/rule/setting (Muninn is half-way there; UUIDs already exist). De-risks sync, enables merge-on-load
   even for a plain folder-sync, and is the prerequisite for *any* backend.
2. **Extract `MuninnSync`** — a platform-agnostic Swift package (models + merge + a swappable transport
   protocol) that both the AppKit Mac app and a future SwiftUI iOS app import. Teasing the data out of
   `AppShell`'s AppKit is the un-sexy but pivotal refactor.
Do these first; the server + iOS app follow, and the transport (own relay → CloudKit/P2P later) stays
swappable.

### The $99 thread (ties to [[self-update]])
Mobile **mandates** the $99 Apple Developer Program (iOS distribution; free provisioning expires apps in
7 days). Paying it once unlocks a cluster: iOS distribution **+** APNs for background sync **+** Developer
ID for the self-update backlog item **+** App Store. Three separate explorations (self-update, mobile,
sync) all terminate at this one gate — worth a deliberate decision when the time comes.
