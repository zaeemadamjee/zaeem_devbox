#!/usr/bin/env bash
# clone-repos.sh — Clone repos into ~/workspace/ based on profile config.
#
# Runs automatically on first zshrc load (see ~/.repos-cloned marker).
# Reads repo URLs from GCE instance metadata (set by Terraform from the profile).
# Safe to re-run — skips repos that already exist.

set -euo pipefail

WORKSPACE="$HOME/workspace"
mkdir -p "$WORKSPACE"

METADATA_ROOT="http://metadata.google.internal/computeMetadata/v1"
METADATA_HEADER="Metadata-Flavor: Google"

# Read newline-separated repo URLs from instance metadata
REPOS_RAW=$(curl -sf \
  -H "$METADATA_HEADER" \
  "$METADATA_ROOT/instance/attributes/devbox-repos" 2>/dev/null || echo "")

if [[ -z "$REPOS_RAW" ]]; then
  echo "==> No repos configured in instance metadata, skipping."
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
