#!/usr/bin/env bash
# reset.sh — Wipe and recreate a devbox VM (fresh disk, full bootstrap on next login).
#
# Usage: ./scripts/reset.sh --profile <name>
#
# Taints the Terraform VM resource and re-applies, destroying and recreating
# only the compute instance. Service account, IAM, and firewall are left intact.

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/lib/profile.sh"

PROFILE=$(parse_profile_flag "$@")
load_profile "$PROFILE"
check_gcp_project

echo
gum style --border rounded --padding "1 2" --border-foreground 202 \
  "$(gum style --foreground 202 --bold "⚠  DESTRUCTIVE OPERATION")" \
  "" \
  "  This will DESTROY and RECREATE: $(gum style --bold "$GCP_INSTANCE_NAME")  (profile: $PROFILE_NAME)" \
  "  All data on the VM disk will be permanently lost."
echo

if ! gum confirm "Destroy and recreate $GCP_INSTANCE_NAME?"; then
  warn "Aborted."
  exit 0
fi

section "Terraform"
terraform_init_profile

setup_tfvars

cd "$TERRAFORM_DIR"

gum spin --spinner dot --title " Tainting VM resource..." -- \
  terraform taint google_compute_instance.devbox
ok "VM resource tainted"

echo
gum style --foreground 244 "  Terraform will show the plan below and ask for confirmation."
echo

terraform apply -var-file="$TMPVARS"

echo
gum style --border rounded --padding "1 2" --border-foreground 46 \
  "$(gum style --foreground 46 --bold "✓  $GCP_INSTANCE_NAME recreated")" \
  "" \
  "$(gum style --foreground 240 "Next:  ./scripts/start.sh --profile $PROFILE_NAME")"
echo
