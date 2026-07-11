# Muninn Handoff Kit

Everything a fresh Claude Code session needs to start building the Muninn browser. Assembled 2026-07-11 from the completed spike phase.

## How to prime a session

1. Create the new project directory (suggested: `~/Code/muninn`) and copy this kit's contents into it — `CLAUDE.md` at the repo root is the priming document; Claude Code loads it automatically.
2. `git init` (or use the new-project skill to create the GitHub repo with branch protection).
3. Open Claude Code in that directory and say something like: *"Read the product brief and research, then start the Planning phase — draft the PRD for my approval."*

The session will find its footing from the artifacts alone; no chat history needed.

## Contents

| File | What it is |
|---|---|
| `CLAUDE.md` | Project instructions for the new repo: state of the pipeline, ground rules, technical facts, first milestone |
| `product-brief.md` | Analysis-phase output → input for the PRD |
| `decisions.md` | Locked decisions: name (Muninn), engine (WKWebView + shim), language split, fallbacks, naming-sweep record |
| `research/spike-a-results.md` | Engine spike: CEF/JCEF × Proton Pass, signed off 2026-07-11 |
| `research/spike-b-proton-pass-api-inventory.md` | The shim spec: Pass's WebExtensions API surface, tiered |
| `research/evidence/` | DevTools target captures + JCEF stderr backing Spike A's claims |

## Pending human actions (not for Claude)

- Register `muninnbrowser.app` / `muninnbrowser.com` (were available 2026-07-11); optionally pursue `muninn.app` from its holder.
- Trademark counsel pass on "Muninn" before any public release.
- Apple Developer account/team for signing, notarization, and the entitlements the shim needs.

## What stays behind in `browser-spike-a/`

The spike harnesses (cefclient, JCEF/Scala, fetched extension) remain in the spike directory for reference; they are not part of Muninn's codebase. The `extension/` dir there contains the unpacked Pass v1.38.2 bundle — useful for shim development, but fetch a fresh one (`01-fetch-extension.sh`) when implementation starts.
