#!/usr/bin/env bash
# reset.sh — Wipe and recreate the dev box VM (fresh disk, full bootstrap on next login).
#
# Taints the Terraform VM resource and re-applies, destroying and recreating
# only the compute instance. Service account, IAM, and firewall are left intact.
#
# Usage: ./scripts/reset.sh

set -euo pipefail

TERRAFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"

echo "==> This will DESTROY and RECREATE the zaeem-devbox VM."
echo "    All data on the VM disk will be permanently lost."
echo ""
read -r -p "    Are you sure? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "==> Tainting VM resource..."
cd "$TERRAFORM_DIR"
terraform taint google_compute_instance.devbox

echo "==> Applying Terraform (this will destroy and recreate the VM)..."
terraform apply -auto-approve

echo ""
echo "==> Done. VM has been recreated with a fresh disk."
echo "    Run ./scripts/start.sh to boot it — bootstrap will run on first SSH login."
