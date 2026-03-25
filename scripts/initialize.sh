#!/usr/bin/env bash
# initialize.sh — First-time provisioning of a devbox VM.
#
# Usage: ./scripts/initialize.sh --profile <name>
#
# Runs all setup steps in order:
#   1. Enable required GCP APIs
#   2. Generate SSH key (if missing) and confirm it's in the profile
#   3. Create the Terraform state bucket (if missing)
#   4. terraform init, import any pre-existing GCP resources, then terraform apply
#
# All steps are idempotent — safe to re-run.
# For subsequent wipe-and-recreate of an existing VM, use reset.sh instead.

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/lib/profile.sh"
source "$SCRIPTS_DIR/lib/ui.sh"
require_gum

PROFILE=$(parse_profile_flag "$@")
load_profile "$PROFILE"
check_gcp_project

SSH_KEY_PATH="$HOME/.ssh/zaeem_devbox"

# ---------------------------------------------------------------------------
# 0. Validate region
# ---------------------------------------------------------------------------
section "Validate"

if ! gcloud compute regions describe "$GCP_REGION" --project="$GCP_PROJECT" &>/dev/null; then
  fail "Region '$GCP_REGION' is not valid in project '$GCP_PROJECT'."
  echo "" >&2
  echo "  Valid regions:" >&2
  gcloud compute regions list --project="$GCP_PROJECT" --format="value(name)" | sort | sed 's/^/    /' >&2
  echo "" >&2
  exit 1
fi
ok "Region '$GCP_REGION' is valid"

# ---------------------------------------------------------------------------
# 1. Enable required GCP APIs
# ---------------------------------------------------------------------------
section "Step 1/4 — GCP APIs"

for api in compute.googleapis.com storage.googleapis.com; do
  if gcloud services list --project="$GCP_PROJECT" \
       --filter="name:${api}" --format="value(name)" 2>/dev/null | grep -q "$api"; then
    skip "$api (already enabled)"
  else
    gum spin --spinner dot --title "  Enabling ${api}..." -- \
      gcloud services enable "$api" --project="$GCP_PROJECT"
    ok "$api enabled"
  fi
done

# ---------------------------------------------------------------------------
# 2. Generate SSH key and confirm it's in the profile
# ---------------------------------------------------------------------------
section "Step 2/4 — SSH key"

if [[ -f "$SSH_KEY_PATH" ]]; then
  skip "SSH key already exists at $SSH_KEY_PATH"
else
  gum spin --spinner dot --title "  Generating ed25519 SSH key..." -- \
    ssh-keygen -t ed25519 -C "zaeem-devbox" -f "$SSH_KEY_PATH" -N ""
  ok "SSH key generated at $SSH_KEY_PATH"
fi

PUBLIC_KEY=$(cat "${SSH_KEY_PATH}.pub")

if printf '%s\n' "${SSH_PUBLIC_KEYS[@]+"${SSH_PUBLIC_KEYS[@]}"}" | grep -qF "$PUBLIC_KEY"; then
  skip "Public key already in profile '$PROFILE_NAME'"
else
  echo
  warn "Your public key is not yet in the profile's SSH_PUBLIC_KEYS."
  echo
  gum style --foreground 240 "  Add this line to scripts/profiles/${PROFILE_NAME}.sh:"
  echo
  gum style --foreground 99 "  \"${PUBLIC_KEY}\""
  echo
  gum confirm "Press Enter once you've added the key, or Ctrl-C to abort" --affirmative="Continue" --negative="Abort" || exit 0

  # Re-source to pick up the change
  source "$SCRIPTS_DIR/profiles/${PROFILE_NAME}.sh"
  if ! printf '%s\n' "${SSH_PUBLIC_KEYS[@]+"${SSH_PUBLIC_KEYS[@]}"}" | grep -qF "$PUBLIC_KEY"; then
    fail "Public key still not found in profile. Please add it and re-run."
    exit 1
  fi
  ok "Public key confirmed in profile"
fi

# ---------------------------------------------------------------------------
# 3. Create Terraform state bucket
# ---------------------------------------------------------------------------
section "Step 3/4 — Terraform state bucket"

BUCKET_NAME="${GCP_PROJECT}-zaeem-devbox-tf-state"
BUCKET_URI="gs://${BUCKET_NAME}"

if gcloud storage buckets describe "$BUCKET_URI" --project="$GCP_PROJECT" &>/dev/null; then
  skip "Bucket $BUCKET_URI already exists"
else
  gum spin --spinner dot --title "  Creating bucket $BUCKET_URI..." -- bash -c "
    gcloud storage buckets create '$BUCKET_URI' \
      --project='$GCP_PROJECT' \
      --location='US' \
      --uniform-bucket-level-access
    gcloud storage buckets update '$BUCKET_URI' --versioning
  "
  ok "Bucket created with versioning enabled"
fi

# ---------------------------------------------------------------------------
# 4. Terraform init + import existing resources + apply
# ---------------------------------------------------------------------------
section "Step 4/4 — Terraform"

terraform_init_profile

TMPVARS="/tmp/devbox-profile-${PROFILE_NAME}.tfvars"
trap 'rm -f "$TMPVARS"' EXIT
generate_tfvars "$TMPVARS"

cd "$TERRAFORM_DIR"

# Import pre-existing shared resources so Terraform doesn't try to recreate them.
SA_EMAIL="otelcol-exporter@${GCP_PROJECT}.iam.gserviceaccount.com"
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$GCP_PROJECT" &>/dev/null; then
  if ! terraform state show google_service_account.otelcol &>/dev/null; then
    gum spin --spinner dot --title "  Importing existing service account..." -- \
      terraform import -var-file="$TMPVARS" \
        google_service_account.otelcol \
        "projects/${GCP_PROJECT}/serviceAccounts/${SA_EMAIL}"
    ok "Service account imported"
  else
    skip "Service account already in state"
  fi
fi

if gcloud compute firewall-rules describe "devbox-allow-ssh" --project="$GCP_PROJECT" &>/dev/null 2>&1; then
  if ! terraform state show google_compute_firewall.allow_ssh &>/dev/null; then
    gum spin --spinner dot --title "  Importing existing firewall rule..." -- \
      terraform import -var-file="$TMPVARS" \
        google_compute_firewall.allow_ssh \
        "projects/${GCP_PROJECT}/global/firewalls/devbox-allow-ssh"
    ok "Firewall rule imported"
  else
    skip "Firewall rule already in state"
  fi
fi

if gcloud compute instances describe "$GCP_INSTANCE_NAME" \
     --zone="$GCP_ZONE" --project="$GCP_PROJECT" &>/dev/null 2>&1; then
  if ! terraform state show google_compute_instance.devbox &>/dev/null; then
    gum spin --spinner dot --title "  Importing existing VM instance..." -- \
      terraform import -var-file="$TMPVARS" \
        google_compute_instance.devbox \
        "${GCP_PROJECT}/${GCP_ZONE}/${GCP_INSTANCE_NAME}"
    ok "VM instance imported"
  else
    skip "VM instance already in state"
  fi
fi

echo
gum style --foreground 244 "  Terraform will show the plan below and ask for confirmation."
echo

terraform apply -var-file="$TMPVARS"

echo
gum style --border rounded --padding "1 2" --border-foreground 46 \
  "$(gum style --foreground 46 --bold "✓  VM provisioned successfully")" \
  "" \
  "$(gum style --foreground 240 "Next:  ./scripts/start.sh --profile $PROFILE_NAME")" \
  "$(gum style --foreground 240 "       (bootstrap runs interactively on first SSH login)")"
echo
