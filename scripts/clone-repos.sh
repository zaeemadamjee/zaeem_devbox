#!/usr/bin/env bash
# clone-repos.sh — Clone repos into ~/workspace/ based on profile config.
#
# Runs automatically on first zshrc load (see ~/.repos-cloned marker).
# Reads repo URLs from GCE instance metadata (set by Terraform from the profile).
# Safe to re-run — skips repos that already exist.
#
# Exit codes:
#   0 — success (all repos cloned, or no repos configured)
#   1 — transient error (metadata unreachable, git clone failed) — will retry on next login

set -euo pipefail

WORKSPACE="$HOME/workspace"
mkdir -p "$WORKSPACE"

METADATA_ROOT="http://metadata.google.internal/computeMetadata/v1"
METADATA_HEADER="Metadata-Flavor: Google"
METADATA_TMP=$(mktemp)
trap 'rm -f "$METADATA_TMP"' EXIT

# Fetch repos from instance metadata, capturing HTTP status separately
HTTP_STATUS=$(curl -s \
  -H "$METADATA_HEADER" \
  -o "$METADATA_TMP" \
  -w "%{http_code}" \
  "$METADATA_ROOT/instance/attributes/devbox-repos" 2>/dev/null || echo "000")

if [[ "$HTTP_STATUS" == "404" ]]; then
  echo "==> No repos configured in instance metadata, skipping."
  exit 0
elif [[ "$HTTP_STATUS" != "200" ]]; then
  echo "==> Could not fetch repos metadata (HTTP $HTTP_STATUS) — will retry on next login."
  exit 1
fi

REPOS_RAW=$(cat "$METADATA_TMP")
if [[ -z "$REPOS_RAW" ]]; then
  echo "==> No repos configured, skipping."
  exit 0
fi

echo "==> Cloning repos into $WORKSPACE..."
while IFS= read -r repo_url; do
  [[ -z "$repo_url" ]] && continue
  repo_name=$(basename "$repo_url" .git)
  dest="$WORKSPACE/$repo_name"
  if [ -d "$dest" ]; then
    echo "  [skip] $repo_name (already exists)"
  else
    echo "  [clone] $repo_url"
    git clone "$repo_url" "$dest"
  fi
done <<< "$REPOS_RAW"

echo "==> Done."
