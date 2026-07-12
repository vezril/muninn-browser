#!/bin/bash
# regrep-inventory.sh — FR-25 parity-canary gate (Spike B methodology).
#
# Shallow/sparse-clones ProtonMail/WebClients (main), re-runs the grep
# inventory of browser.<ns>.<member> call sites over applications/pass-extension
# and packages/pass, extracts the Safari-manifest permission profile, and writes
# a dated artifact to research/regrep/YYYY-MM-DD.md containing the inventory,
# the diff against tools/regrep-baseline.txt, and a triage section.
#
# Loud failure on clone/network problems — a silent empty artifact must never
# satisfy the gate (parity-canary spec).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE="$REPO_ROOT/tools/regrep-baseline.txt"
OUT_DIR="$REPO_ROOT/research/regrep"
OUT="$OUT_DIR/$(date +%Y-%m-%d).md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$BASELINE" ] || { echo "ERROR: baseline $BASELINE missing." >&2; exit 1; }

echo "Cloning ProtonMail/WebClients (shallow, sparse)..."
if ! git clone --quiet --depth 1 --filter=blob:none --sparse \
    https://github.com/ProtonMail/WebClients "$WORK/WebClients"; then
  echo "ERROR: clone failed (network?). No artifact written." >&2
  exit 1
fi
git -C "$WORK/WebClients" sparse-checkout set \
  applications/pass-extension packages/pass 2>/dev/null

SRC="$WORK/WebClients"
COMMIT="$(git -C "$SRC" rev-parse HEAD)"
PASS_VERSION="$(jq -r .version "$SRC/applications/pass-extension/manifest-chrome.json" 2>/dev/null || echo unknown)"

# Sanity: the sparse checkout actually contains sources.
[ -d "$SRC/applications/pass-extension/src" ] || {
  echo "ERROR: sparse checkout incomplete (applications/pass-extension/src missing). No artifact written." >&2
  exit 1
}

# Inventory: browser.<ns>.<member> and chrome.<ns>.<member> call sites.
INVENTORY="$WORK/inventory.txt"
grep -rhoE '\b(browser|chrome)\.[a-zA-Z]+\.[a-zA-Z]+' \
    "$SRC/applications/pass-extension" "$SRC/packages/pass" \
    --include='*.ts' --include='*.tsx' --include='*.js' 2>/dev/null \
  | sed -E 's/^(browser|chrome)\.//' \
  | grep -E '^(action|alarms|commands|nativeMessaging|offscreen|permissions|privacy|runtime|scripting|storage|tabs|webNavigation|webRequest|windows)\.' \
  | sort | uniq -c | sort -rn > "$INVENTORY"

[ -s "$INVENTORY" ] || { echo "ERROR: inventory came back empty — grep or layout changed. No artifact written." >&2; exit 1; }

CURRENT_SET="$WORK/current-set.txt"
awk '{print $2}' "$INVENTORY" | sort -u > "$CURRENT_SET"
BASELINE_SET="$WORK/baseline-set.txt"
grep -v '^#' "$BASELINE" | grep -v '^$' | sort -u > "$BASELINE_SET"

NEW_ENTRIES="$(comm -13 "$BASELINE_SET" "$CURRENT_SET" || true)"
GONE_ENTRIES="$(comm -23 "$BASELINE_SET" "$CURRENT_SET" || true)"

mkdir -p "$OUT_DIR"
{
  echo "# FR-25 re-grep artifact — $(date +%Y-%m-%d)"
  echo
  echo "- WebClients commit: \`$COMMIT\`"
  echo "- Pass extension version (manifest-chrome.json): \`$PASS_VERSION\`"
  echo "- Vendored bundle version: \`$(jq -r .extensionVersion "$REPO_ROOT/vendor/pass-extension/MANIFEST.lock" 2>/dev/null || echo 'not vendored')\`"
  echo "- Baseline: Spike B (2026-07-11, v1.38.2) via \`tools/regrep-baseline.txt\`"
  echo
  echo "## Safari-manifest permission profile"
  echo
  echo '```json'
  jq '{permissions, host_permissions, optional_permissions}' "$SRC/applications/pass-extension/manifest-safari.json" 2>/dev/null || echo '"manifest-safari.json not found — INVESTIGATE (AS-1 canary!)"'
  echo '```'
  echo
  echo "## Call-site inventory (browser.*/chrome.* members, by count)"
  echo
  echo '```'
  cat "$INVENTORY"
  echo '```'
  echo
  echo "## Diff vs baseline"
  echo
  if [ -z "$NEW_ENTRIES" ] && [ -z "$GONE_ENTRIES" ]; then
    echo "**No diff** — the API surface matches the Spike B baseline. Gate satisfied once this artifact is committed."
  else
    echo "### NEW (must be triaged Tier 1/2/3 below before shim work proceeds)"
    echo
    if [ -n "$NEW_ENTRIES" ]; then echo "$NEW_ENTRIES" | sed 's/^/- [ ] `/;s/$/` — TRIAGE: /'; else echo "_none_"; fi
    echo
    echo "### RETIRED (in baseline, no longer found — note, no action required)"
    echo
    if [ -n "$GONE_ENTRIES" ]; then echo "$GONE_ENTRIES" | sed 's/^/- `/;s/$/`/'; else echo "_none_"; fi
  fi
  echo
  echo "## Triage"
  echo
  echo "_Every NEW entry above must carry a Tier 1/2/3 disposition before E2+ work starts (FR-25). Add dispositions inline on the checkboxes, then summarize here._"
} > "$OUT"

echo "Wrote $OUT"
if [ -n "$NEW_ENTRIES" ]; then
  echo
  echo "*** NEW API surface found — triage required before the gate is satisfied: ***"
  echo "$NEW_ENTRIES"
fi
