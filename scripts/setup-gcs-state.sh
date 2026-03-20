#!/usr/bin/env bash
# =============================================================================
# setup-gcs-state.sh
#
# Creates the shared GCS bucket used for Terraform remote state.
# Run once before first `terraform init` on any profile.
#
# State is stored per profile under:
#   gs://zaeem-devbox-tf-state/<profile-name>/terraform.tfstate
#
# Uses the currently active gcloud project — make sure you're logged in to
# the right project before running this.
#
# Usage:
#   ./scripts/setup-gcs-state.sh
# =============================================================================

set -euo pipefail

LOCATION="US"

PROJECT=$(gcloud config get-value project 2>/dev/null)
if [[ -z "$PROJECT" ]]; then
  echo "Error: no active gcloud project."
  echo "Run: gcloud config set project <project-id>"
  exit 1
fi

BUCKET_NAME="${PROJECT}-zaeem-devbox-tf-state"
BUCKET_URI="gs://${BUCKET_NAME}"

echo "==> Checking for existing GCS bucket: ${BUCKET_URI} (project: ${PROJECT})"

if gcloud storage buckets describe "${BUCKET_URI}" --project="${PROJECT}" &>/dev/null; then
  echo "    Bucket ${BUCKET_URI} already exists — skipping creation."
else
  echo "==> Creating bucket ${BUCKET_URI} in location ${LOCATION}..."
  gcloud storage buckets create "${BUCKET_URI}" \
    --project="${PROJECT}" \
    --location="${LOCATION}" \
    --uniform-bucket-level-access

  echo "==> Enabling versioning on ${BUCKET_URI}..."
  gcloud storage buckets update "${BUCKET_URI}" \
    --versioning

  echo "    Bucket created and versioning enabled."
fi

echo ""
echo "==> Success! GCS state bucket is ready: ${BUCKET_URI}"
echo ""
echo "Next steps:"
echo "  1. Create a profile in scripts/profiles/<name>.sh"
echo "  2. Run: ./scripts/start.sh --profile <name>"
