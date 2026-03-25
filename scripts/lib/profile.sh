#!/usr/bin/env bash
# lib/profile.sh — Shared profile loading and Terraform helpers for devbox scripts.
#
# Source this file at the top of each operational script:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/profile.sh"   # from scripts/
#   source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib/profile.sh"  # from elsewhere

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"

# ---------------------------------------------------------------------------
# parse_profile_flag "$@"
#   Extracts the value of --profile/-p from the script's arguments.
#   Prints the profile name to stdout. Exits with error if not provided.
# ---------------------------------------------------------------------------
parse_profile_flag() {
  local profile=""
  local i=0
  local args=("$@")
  while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
      --profile|-p)
        i=$((i + 1))
        profile="${args[$i]:-}"
        ;;
    esac
    i=$((i + 1))
  done

  if [[ -z "$profile" ]]; then
    echo "" >&2
    echo "  Error: --profile <name> is required" >&2
    echo "" >&2
    _list_profiles >&2
    exit 1
  fi

  echo "$profile"
}

# ---------------------------------------------------------------------------
# load_profile <name>
#   Sources scripts/profiles/<name>.sh and validates required variables.
# ---------------------------------------------------------------------------
load_profile() {
  local profile_name="$1"
  local profile_file="$SCRIPTS_DIR/profiles/${profile_name}.sh"

  if [[ ! -f "$profile_file" ]]; then
    echo "" >&2
    echo "  Error: Profile not found: '$profile_name'" >&2
    echo "" >&2
    _list_profiles >&2
    exit 1
  fi

  source "$profile_file"

  # Validate required scalar variables
  local required=(PROFILE_NAME GCP_PROJECT GCP_REGION GCP_INSTANCE_NAME VM_MACHINE_TYPE VM_DISK_SIZE IDLE_TIMER_ENABLED)
  for var in "${required[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      echo "  Error: Profile '$profile_name' is missing required variable: $var" >&2
      exit 1
    fi
  done

  # GCP_ZONE is optional — if unset, Terraform picks one from the region
  GCP_ZONE="${GCP_ZONE:-}"

  # STATIC_IP is optional — defaults to false (ephemeral IP)
  STATIC_IP="${STATIC_IP:-false}"

  # Default optional arrays to empty if unset
  SSH_PUBLIC_KEYS=("${SSH_PUBLIC_KEYS[@]+"${SSH_PUBLIC_KEYS[@]}"}")
  REPOS=("${REPOS[@]+"${REPOS[@]}"}")
}

# ---------------------------------------------------------------------------
# check_gcp_project
#   Validates that the active gcloud project matches the profile's GCP_PROJECT.
#   Call after load_profile.
# ---------------------------------------------------------------------------
check_gcp_project() {
  local active_project
  active_project=$(gcloud config get-value project 2>/dev/null)

  if [[ "$active_project" != "$GCP_PROJECT" ]]; then
    echo "" >&2
    echo "  Error: GCP project mismatch" >&2
    echo "" >&2
    printf "  Profile '%-30s expects project: %s\n" "${PROFILE_NAME}'" "$GCP_PROJECT" >&2
    printf "  Currently active project:%*s%s\n" 16 "" "$active_project" >&2
    echo "" >&2
    echo "  Fix: gcloud config set project $GCP_PROJECT" >&2
    echo "" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# resolve_instance_zone
#   If GCP_ZONE is empty, looks up the zone of the existing VM instance.
#   Required before gcloud commands that need --zone (start, stop).
#   Exits with an error if the instance cannot be found.
# ---------------------------------------------------------------------------
resolve_instance_zone() {
  if [[ -n "$GCP_ZONE" ]]; then
    return
  fi
  GCP_ZONE=$(gcloud compute instances list \
    --project="$GCP_PROJECT" \
    --filter="name=${GCP_INSTANCE_NAME}" \
    --format="value(zone)" 2>/dev/null | head -1)
  if [[ -z "$GCP_ZONE" ]]; then
    echo "  Error: Could not find instance '$GCP_INSTANCE_NAME' in project '$GCP_PROJECT'." >&2
    echo "  Has the VM been provisioned? Run: ./scripts/initialize.sh --profile $PROFILE_NAME" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# terraform_init_profile
#   Runs terraform init with the correct backend config for this profile.
#   State is stored at gs://<project-id>-zaeem-devbox-tf-state/<profile-name>/
# ---------------------------------------------------------------------------
terraform_init_profile() {
  local bucket="${GCP_PROJECT}-zaeem-devbox-tf-state"
  echo "==> Initializing Terraform for profile '$PROFILE_NAME'..."
  cd "$TERRAFORM_DIR"
  terraform init -reconfigure \
    -backend-config="bucket=${bucket}" \
    -backend-config="prefix=${PROFILE_NAME}" \
    -input=false \
    -no-color > /dev/null
  echo "    State: gs://${bucket}/${PROFILE_NAME}"

}

# ---------------------------------------------------------------------------
# generate_tfvars <output-file>
#   Writes all profile variables to an HCL .tfvars file for use with
#   terraform apply -var-file=<output-file>.
# ---------------------------------------------------------------------------
generate_tfvars() {
  local tmpfile="$1"

  # Build HCL list for ssh_public_keys
  local ssh_keys_hcl
  ssh_keys_hcl=$(_build_hcl_list "${SSH_PUBLIC_KEYS[@]+"${SSH_PUBLIC_KEYS[@]}"}")

  # Build HCL list for repos
  local repos_hcl
  repos_hcl=$(_build_hcl_list "${REPOS[@]+"${REPOS[@]}"}")

  cat > "$tmpfile" <<EOF
project_id         = "${GCP_PROJECT}"
region             = "${GCP_REGION}"
zone               = "${GCP_ZONE}"
instance_name      = "${GCP_INSTANCE_NAME}"
machine_type       = "${VM_MACHINE_TYPE}"
disk_size          = ${VM_DISK_SIZE}
idle_timer_enabled = ${IDLE_TIMER_ENABLED}
static_ip          = ${STATIC_IP}
profile_name       = "${PROFILE_NAME}"
ssh_public_keys    = ${ssh_keys_hcl}
repos              = ${repos_hcl}
EOF
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------
_list_profiles() {
  local profiles_dir="$SCRIPTS_DIR/profiles"
  if compgen -G "$profiles_dir/*.sh" > /dev/null 2>&1; then
    echo "  Available profiles:"
    for f in "$profiles_dir"/*.sh; do
      echo "    $(basename "$f" .sh)"
    done
  else
    echo "  No profiles found in scripts/profiles/"
  fi
  echo ""
}

_build_hcl_list() {
  # Builds an HCL list literal from the given values.
  # Usage: _build_hcl_list "${MY_ARRAY[@]}"
  if [[ $# -eq 0 ]]; then
    echo "[]"
    return
  fi
  local result="["$'\n'
  for item in "$@"; do
    result+="  \"${item}\","$'\n'
  done
  result+="]"
  echo "$result"
}
