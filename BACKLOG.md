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
