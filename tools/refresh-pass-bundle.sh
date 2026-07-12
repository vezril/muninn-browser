#!/bin/bash
# refresh-pass-bundle.sh — ADR-001: extract/refresh the vendored Safari-target
# Proton Pass extension web bundle from the locally-installed
# "Proton Pass for Safari.app" (Mac App Store).
#
# - No-op when the installed version equals the lockfile version.
# - On a version change: extracts the web-bundle subset (Proton-native
#   *.bundle payloads excluded) to vendor/pass-extension/<version>/,
#   rewrites MANIFEST.lock, prints a manifest.json diff, and reminds the
#   operator that FR-25's re-grep gate must run before shim code uses the
#   new bundle.
# - Never installs anything; a missing source app is a loud, actionable error.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPEX="/Applications/Proton Pass for Safari.app/Contents/PlugIns/Safari Extension.appex/Contents/Resources"
VENDOR_DIR="$REPO_ROOT/vendor/pass-extension"
LOCK="$VENDOR_DIR/MANIFEST.lock"

if [ ! -d "$APPEX" ]; then
  cat >&2 <<'EOF'
ERROR: "Proton Pass for Safari.app" is not installed (appex Resources not found).

The vendored bundle's source is the Mac App Store app (free):
  https://apps.apple.com/us/app/proton-pass-for-safari/id6502835663
Installing it is a manual human action (CLAUDE.md ground rule 5) — this
script never installs software. Install/update it, then re-run.
EOF
  exit 1
fi

command -v jq >/dev/null || { echo "ERROR: jq is required." >&2; exit 1; }

INSTALLED_VERSION="$(jq -r .version "$APPEX/manifest.json")"
[ -n "$INSTALLED_VERSION" ] && [ "$INSTALLED_VERSION" != "null" ] || {
  echo "ERROR: could not read extension version from $APPEX/manifest.json" >&2
  exit 1
}

LOCKED_VERSION=""
[ -f "$LOCK" ] && LOCKED_VERSION="$(jq -r .extensionVersion "$LOCK")"

if [ "$INSTALLED_VERSION" = "$LOCKED_VERSION" ]; then
  echo "Vendored Pass bundle is up to date (v$INSTALLED_VERSION). Nothing to do."
  exit 0
fi

DEST="$VENDOR_DIR/$INSTALLED_VERSION"
echo "Extracting Pass extension v$INSTALLED_VERSION (was: ${LOCKED_VERSION:-none}) -> $DEST"
rm -rf "$DEST"
mkdir -p "$DEST"
# Web-bundle subset only: exclude Proton's native resource bundles.
rsync -a --exclude='*.bundle' "$APPEX/" "$DEST/"

# Deterministic aggregate sha256 over the extracted tree.
TREE_SHA="$(cd "$DEST" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -d' ' -f1)"
FILE_COUNT="$(find "$DEST" -type f | wc -l | tr -d ' ')"

jq -n \
  --arg source "safari-appex" \
  --arg sourcePath "$APPEX" \
  --arg version "$INSTALLED_VERSION" \
  --arg webClientsRef "proton-pass@$INSTALLED_VERSION (presumed release tag; MAS artifact carries no commit)" \
  --arg sha256 "$TREE_SHA" \
  --arg extractedAt "$(date +%Y-%m-%d)" \
  --argjson files "$FILE_COUNT" \
  '{source: $source, sourcePath: $sourcePath, extensionVersion: $version, webClientsRef: $webClientsRef, sha256: $sha256, extractedAt: $extractedAt, files: $files}' \
  > "$LOCK"

echo "Wrote $LOCK (sha256 $TREE_SHA, $FILE_COUNT files)."

if [ -n "$LOCKED_VERSION" ] && [ -d "$VENDOR_DIR/$LOCKED_VERSION" ]; then
  echo
  echo "=== manifest.json diff (v$LOCKED_VERSION -> v$INSTALLED_VERSION) ==="
  diff <(jq -S . "$VENDOR_DIR/$LOCKED_VERSION/manifest.json") \
       <(jq -S . "$DEST/manifest.json") || true
  echo
  echo "Superseded version v$LOCKED_VERSION left in place — prune it once the new bundle is validated."
fi

cat <<EOF

*** FR-25 GATE REMINDER ***
A version bump requires the parity-canary re-grep (tools/regrep-inventory.sh)
to run and be triaged BEFORE any shim code uses this bundle. See prd.md FR-25
and openspec/specs (parity-canary).
EOF
