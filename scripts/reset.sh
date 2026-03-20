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

echo "==> This will DESTROY and RECREATE $GCP_INSTANCE_NAME (profile: $PROFILE_NAME)."
echo "    All data on the VM disk will be permanently lost."
echo ""
read -r -p "    Are you sure? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo ""
terraform_init_profile

# Write profile vars to a temp file and clean up on exit
TMPVARS=$(mktemp /tmp/devbox-profile-XXXXXX.tfvars)
trap 'rm -f "$TMPVARS"' EXIT
generate_tfvars "$TMPVARS"

echo "==> Tainting VM resource..."
cd "$TERRAFORM_DIR"
terraform taint google_compute_instance.devbox

echo "==> Applying Terraform (this will destroy and recreate the VM)..."
terraform apply -var-file="$TMPVARS" -auto-approve

echo ""
echo "==> Done. VM has been recreated with a fresh disk."
echo "    Run ./scripts/start.sh --profile $PROFILE_NAME to boot it — bootstrap will run on first SSH login."
