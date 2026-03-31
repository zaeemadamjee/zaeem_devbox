#!/usr/bin/env bash
# stop.sh — Manually stop a devbox VM.
#
# Usage: ./scripts/stop.sh --profile <name>
#
# The VM also auto-stops after 20 minutes of idle (via systemd timer, if enabled).
# Use this script to stop it immediately.

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/lib/profile.sh"

PROFILE=$(parse_profile_flag "$@")
load_profile "$PROFILE"
check_gcp_project
check_gcloud_auth
resolve_instance_zone

gum spin --spinner dot --title "Stopping $GCP_INSTANCE_NAME (profile: $PROFILE_NAME)..." -- \
  gcloud compute instances stop "$GCP_INSTANCE_NAME" \
    --zone="$GCP_ZONE" --project="$GCP_PROJECT" --quiet

ok "$GCP_INSTANCE_NAME stopped  $(gum style --faint "(disk persists, no compute charges until next start)")"
