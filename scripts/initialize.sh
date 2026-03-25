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

PROFILE=$(parse_profile_flag "$@")
load_profile "$PROFILE"
check_gcp_project

SSH_KEY_PATH="$HOME/.ssh/zaeem_devbox"

info()    { printf '\033[0;34m[INFO]\033[0m  %s\n' "$*"; }
success() { printf '\033[0;32m[OK]\033[0m    %s\n' "$*"; }
warn()    { printf '\033[0;33m[WARN]\033[0m  %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 0. Validate region
# ---------------------------------------------------------------------------
if ! gcloud compute regions describe "$GCP_REGION" --project="$GCP_PROJECT" &>/dev/null; then
  echo "" >&2
  echo "  Error: '$GCP_REGION' is not a valid GCP region in project '$GCP_PROJECT'." >&2
  echo "" >&2
  echo "  Valid regions:" >&2
  gcloud compute regions list --project="$GCP_PROJECT" --format="value(name)" | sort | sed 's/^/    /' >&2
  echo "" >&2
  exit 1
fi
success "Region '$GCP_REGION' is valid."

# ---------------------------------------------------------------------------
# 1. Enable required GCP APIs
# ---------------------------------------------------------------------------
echo ""
info "Step 1/4 — Enabling required GCP APIs on project '$GCP_PROJECT'..."

for api in compute.googleapis.com storage.googleapis.com; do
  if gcloud services list --project="$GCP_PROJECT" --filter="name:${api}" --format="value(name)" 2>/dev/null | grep -q "$api"; then
    success "  ${api} already enabled."
  else
    info "  Enabling ${api}..."
    gcloud services enable "$api" --project="$GCP_PROJECT"
    success "  ${api} enabled."
  fi
done

# ---------------------------------------------------------------------------
# 2. Generate SSH key and confirm it's in the profile
# ---------------------------------------------------------------------------
echo ""
info "Step 2/4 — SSH key..."

if [[ -f "$SSH_KEY_PATH" ]]; then
  success "SSH key already exists at $SSH_KEY_PATH"
else
  info "Generating ed25519 SSH key at $SSH_KEY_PATH..."
  ssh-keygen -t ed25519 -C "zaeem-devbox" -f "$SSH_KEY_PATH" -N ""
  success "SSH key generated."
fi

PUBLIC_KEY=$(cat "${SSH_KEY_PATH}.pub")

# Check if this machine's public key is already in the profile
if printf '%s\n' "${SSH_PUBLIC_KEYS[@]+"${SSH_PUBLIC_KEYS[@]}"}" | grep -qF "$PUBLIC_KEY"; then
  success "Public key is already in profile '$PROFILE_NAME'."
else
  echo ""
  warn "Your public key is not yet in the profile's SSH_PUBLIC_KEYS."
  echo ""
  echo "  Add the following line to scripts/profiles/${PROFILE_NAME}.sh:"
  echo ""
  echo "  \"${PUBLIC_KEY}\""
  echo ""
  read -r -p "  Press Enter once you've added it, or Ctrl-C to abort: "

  # Re-source the profile to pick up the change
  source "$SCRIPTS_DIR/profiles/${PROFILE_NAME}.sh"
  if ! printf '%s\n' "${SSH_PUBLIC_KEYS[@]+"${SSH_PUBLIC_KEYS[@]}"}" | grep -qF "$PUBLIC_KEY"; then
    echo ""
    echo "  Error: public key still not found in profile. Please add it and re-run." >&2
    exit 1
  fi
  success "Public key confirmed in profile."
fi

# ---------------------------------------------------------------------------
# 3. Create Terraform state bucket
# ---------------------------------------------------------------------------
echo ""
info "Step 3/4 — Terraform state bucket..."

BUCKET_NAME="${GCP_PROJECT}-zaeem-devbox-tf-state"
BUCKET_URI="gs://${BUCKET_NAME}"

if gcloud storage buckets describe "$BUCKET_URI" --project="$GCP_PROJECT" &>/dev/null; then
  success "Bucket $BUCKET_URI already exists."
else
  info "Creating bucket $BUCKET_URI..."
  gcloud storage buckets create "$BUCKET_URI" \
    --project="$GCP_PROJECT" \
    --location="US" \
    --uniform-bucket-level-access
  gcloud storage buckets update "$BUCKET_URI" --versioning
  success "Bucket created with versioning enabled."
fi

# ---------------------------------------------------------------------------
# 4. Terraform init + import existing resources + apply
# ---------------------------------------------------------------------------
echo ""
info "Step 4/4 — Provisioning VM with Terraform..."

terraform_init_profile

TMPVARS=$(mktemp /tmp/devbox-profile-XXXXXX.tfvars)
trap 'rm -f "$TMPVARS"' EXIT
generate_tfvars "$TMPVARS"

cd "$TERRAFORM_DIR"

# Import pre-existing shared resources so Terraform doesn't try to recreate them.
# This is needed when GCP already has resources from a previous deployment but
# the Terraform state for this profile is empty.
SA_EMAIL="otelcol-exporter@${GCP_PROJECT}.iam.gserviceaccount.com"
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$GCP_PROJECT" &>/dev/null; then
  if ! terraform state show google_service_account.otelcol &>/dev/null; then
    info "  Importing existing service account into state..."
    terraform import -var-file="$TMPVARS" \
      google_service_account.otelcol \
      "projects/${GCP_PROJECT}/serviceAccounts/${SA_EMAIL}"
    success "  Service account imported."
  else
    success "  Service account already in state."
  fi
fi

if gcloud compute firewall-rules describe "devbox-allow-ssh" --project="$GCP_PROJECT" &>/dev/null 2>&1; then
  if ! terraform state show google_compute_firewall.allow_ssh &>/dev/null; then
    info "  Importing existing firewall rule into state..."
    terraform import -var-file="$TMPVARS" \
      google_compute_firewall.allow_ssh \
      "projects/${GCP_PROJECT}/global/firewalls/devbox-allow-ssh"
    success "  Firewall rule imported."
  else
    success "  Firewall rule already in state."
  fi
fi

if gcloud compute instances describe "$GCP_INSTANCE_NAME" --zone="$GCP_ZONE" --project="$GCP_PROJECT" &>/dev/null 2>&1; then
  if ! terraform state show google_compute_instance.devbox &>/dev/null; then
    info "  Importing existing VM instance into state..."
    terraform import -var-file="$TMPVARS" \
      google_compute_instance.devbox \
      "${GCP_PROJECT}/${GCP_ZONE}/${GCP_INSTANCE_NAME}"
    success "  VM instance imported."
  else
    success "  VM instance already in state."
  fi
fi

terraform apply -var-file="$TMPVARS"

echo ""
success "VM provisioned successfully."
echo ""
echo "  Next: ./scripts/start.sh --profile $PROFILE_NAME"
echo "        (bootstrap will run automatically on first SSH login)"
