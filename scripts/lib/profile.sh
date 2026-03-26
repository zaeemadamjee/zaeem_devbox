#!/usr/bin/env bash
# lib/profile.sh — Shared profile loading, Terraform helpers, and UI setup.
#
# Source this file at the top of each operational script — it sources lib/ui.sh
# and calls require_gum automatically, so no further setup is needed:
#
#   SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPTS_DIR/lib/profile.sh"

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"

source "$SCRIPTS_DIR/lib/ui.sh"
require_gum

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
    echo >&2
    gum style --foreground 196 "  ✗  --profile <name> is required" >&2
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
    echo >&2
    gum style --foreground 196 "  ✗  Profile not found: '$profile_name'" >&2
    _list_profiles >&2
    exit 1
  fi

  source "$profile_file"

  local required=(PROFILE_NAME GCP_PROJECT GCP_REGION GCP_INSTANCE_NAME VM_MACHINE_TYPE VM_DISK_SIZE IDLE_TIMER_ENABLED)
  for var in "${required[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      gum style --foreground 196 "  ✗  Profile '$profile_name' is missing required variable: $var" >&2
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
    echo >&2
    gum style --border rounded --padding "1 2" --border-foreground 196 \
      "$(gum style --foreground 196 --bold "✗  GCP project mismatch")" \
      "" \
      "  Profile $(gum style --bold "'${PROFILE_NAME}'")" \
      "  Expected:  $(gum style --foreground 46  "$GCP_PROJECT")" \
      "  Active:    $(gum style --foreground 196 "$active_project")" \
      "" \
      "$(gum style --foreground 240 "Fix: gcloud config set project $GCP_PROJECT")" >&2
    echo >&2
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
    echo >&2
    gum style --foreground 196 "  ✗  Instance '$GCP_INSTANCE_NAME' not found in project '$GCP_PROJECT'." >&2
    gum style --foreground 240 "     Has the VM been provisioned? Run: ./scripts/initialize.sh --profile $PROFILE_NAME" >&2
    echo >&2
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
  gum spin --spinner dot --title " Initializing Terraform (profile: $PROFILE_NAME)..." -- \
    bash -c "cd '$TERRAFORM_DIR' && terraform init -reconfigure \
      -backend-config='bucket=${bucket}' \
      -backend-config='prefix=${PROFILE_NAME}' \
      -input=false -no-color > /dev/null"
  ok "Terraform initialized  $(gum style --faint "gs://${bucket}/${PROFILE_NAME}")"
}

# ---------------------------------------------------------------------------
# setup_tfvars
#   Writes profile variables to a deterministic temp file, registers a cleanup
#   trap, and exports TMPVARS for use with terraform apply -var-file="$TMPVARS".
# ---------------------------------------------------------------------------
setup_tfvars() {
  TMPVARS="/tmp/devbox-profile-${PROFILE_NAME}.tfvars"
  trap 'rm -f "$TMPVARS"' EXIT
  generate_tfvars "$TMPVARS"
}

# ---------------------------------------------------------------------------
# generate_tfvars <output-file>
#   Writes all profile variables to an HCL .tfvars file for use with
#   terraform apply -var-file=<output-file>.
# ---------------------------------------------------------------------------
generate_tfvars() {
  local tmpfile="$1"

  local ssh_keys_hcl
  ssh_keys_hcl=$(_build_hcl_list "${SSH_PUBLIC_KEYS[@]+"${SSH_PUBLIC_KEYS[@]}"}")

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
  echo >&2
  if compgen -G "$profiles_dir/*.sh" > /dev/null 2>&1; then
    gum style --foreground 244 "  Available profiles:" >&2
    for f in "$profiles_dir"/*.sh; do
        gum style --foreground 135 "    ·  $(basename "$f" .sh)" >&2
    done
  else
    gum style --foreground 244 "  No profiles found in scripts/profiles/" >&2
  fi
  echo >&2
}

_build_hcl_list() {
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
