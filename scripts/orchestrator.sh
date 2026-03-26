#!/usr/bin/env bash
# orchestrator.sh — Interactive menu to manage devbox VMs.
#
# Usage: ./scripts/orchestrator.sh
#
# Shows GCP auth status and live VM state for all profiles before
# presenting the profile → action menus.

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/lib/profile.sh"

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
echo
gum style --bold --foreground 212 "  ⬡  devbox orchestrator"
echo

# ---------------------------------------------------------------------------
# GCP auth status
# ---------------------------------------------------------------------------
section "GCP"

_gcloud_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1 || true)
_gcloud_project=$(gcloud config get-value project 2>/dev/null | tr -d '[:space:]' || true)

if [[ -z "$_gcloud_account" ]]; then
  fail "Not authenticated — run: gcloud auth login"
  exit 1
fi

ok "$(printf "%-9s" "Account")  $(gum style --foreground 212 "$_gcloud_account")"
ok "$(printf "%-9s" "Project")  $(gum style --foreground 244 "${_gcloud_project:-(none)}")"

# ---------------------------------------------------------------------------
# Discover profiles
# ---------------------------------------------------------------------------
_profile_names=()
for _f in "$SCRIPTS_DIR/profiles/"*.sh; do
  [[ -f "$_f" ]] && _profile_names+=("$(basename "$_f" .sh)")
done

if [[ ${#_profile_names[@]} -eq 0 ]]; then
  echo
  fail "No profiles found in scripts/profiles/"
  exit 1
fi

# ---------------------------------------------------------------------------
# VM status — query all profiles in parallel, collect into temp files
# ---------------------------------------------------------------------------
section "VM Status"

_tmpdir=$(mktemp -d)
trap 'rm -rf "$_tmpdir"' EXIT
printf '%s\n' "${_profile_names[@]}" > "$_tmpdir/profiles.txt"

# Runs inside the gum spin subprocess (exported so bash -c can find it).
_fetch_vm_statuses() {
  local tmpdir="$1" scripts_dir="$2"
  local _active_project
  _active_project=$(gcloud config get-value project 2>/dev/null | tr -d '[:space:]' || true)

  while IFS= read -r _name; do
    (
      # shellcheck source=/dev/null
      source "$scripts_dir/profiles/${_name}.sh" 2>/dev/null || true

      # If the profile's project doesn't match the active gcloud project, we
      # don't have credentials for it — mark it rather than silently showing
      # "not found" due to a permission-denied query failure.
      if [[ "$GCP_PROJECT" != "$_active_project" ]]; then
        printf '%s|WRONG_ACCOUNT||%s|%s\n' \
          "$_name" "$GCP_INSTANCE_NAME" "$VM_MACHINE_TYPE" > "$tmpdir/$_name.txt"
        exit 0
      fi

      _result=$(gcloud compute instances list \
        --project="$GCP_PROJECT" \
        --filter="name=${GCP_INSTANCE_NAME}" \
        --format="csv[no-heading](status,zone.basename(),machineType.basename())" \
        2>/dev/null | head -1 || true)
      if [[ -z "$_result" ]]; then
        printf '%s|NOT_FOUND||%s|%s\n' \
          "$_name" "$GCP_INSTANCE_NAME" "$VM_MACHINE_TYPE" > "$tmpdir/$_name.txt"
      else
        IFS=',' read -r _st _zone _mtype <<< "$_result"
        printf '%s|%s|%s|%s|%s\n' \
          "$_name" "$_st" "$_zone" "$GCP_INSTANCE_NAME" "${_mtype:-$VM_MACHINE_TYPE}" \
          > "$tmpdir/$_name.txt"
      fi
    ) &
  done < "$tmpdir/profiles.txt"
  wait  # wait for all parallel gcloud queries before returning to gum spin
}
export -f _fetch_vm_statuses

gum spin --spinner dot --title " Checking VMs..." -- \
  bash -c "_fetch_vm_statuses '$_tmpdir' '$SCRIPTS_DIR'"

# --- Render status table ---
# Each status string is pre-padded to 10 visible chars before adding ANSI codes.
# This keeps all _status_col values at the same byte length so printf %s
# alignment stays consistent across rows despite the invisible escape codes.
_R=$'\033[0m'
_GREEN=$'\033[32m'
_YELLOW=$'\033[33m'
_CYAN=$'\033[36m'
_GRAY=$'\033[90m'
_DIM=$'\033[2m'

for _name in "${_profile_names[@]}"; do
  if [[ ! -f "$_tmpdir/${_name}.txt" ]]; then
    printf "  \033[31m✗\033[0m  %s  (error fetching status)\n" "$_name"
    continue
  fi

  IFS='|' read -r _pname _status _zone _vm_name _mtype < "$_tmpdir/${_name}.txt"

  case "$_status" in
    RUNNING)
      _sym="${_GREEN}✓${_R}"
      _status_col="${_GREEN}$(printf '%-10s' 'RUNNING')${_R}"
      ;;
    TERMINATED)
      _sym="${_YELLOW}■${_R}"
      _status_col="${_YELLOW}$(printf '%-10s' 'STOPPED')${_R}"
      ;;
    STAGING|PROVISIONING)
      _sym="${_CYAN}↻${_R}"
      _status_col="${_CYAN}$(printf '%-10s' "$_status")${_R}"
      ;;
    WRONG_ACCOUNT)
      _sym="${_YELLOW}⚠${_R}"
      _status_col="${_YELLOW}$(printf '%-10s' 'wrong acct')${_R}"
      ;;
    NOT_FOUND)
      _sym="${_GRAY}·${_R}"
      _status_col="${_GRAY}$(printf '%-10s' 'not found')${_R}"
      ;;
    *)
      _sym="${_YELLOW}⚠${_R}"
      _status_col="${_YELLOW}$(printf '%-10s' "$_status")${_R}"
      ;;
  esac

  # Fixed-width plain fields keep alignment; colored fields are printed
  # without width formatting to avoid byte-count skew from ANSI codes.
  printf "  %s  %-12s  %-26s  %s  ${_DIM}%-14s  %s${_R}\n" \
    "$_sym" "$_pname" "$_vm_name" "$_status_col" "${_zone:--}" "${_mtype:--}"
done

echo

# ---------------------------------------------------------------------------
# Profile selection
# ---------------------------------------------------------------------------
section "Profile"

PROFILE=$(gum choose \
  --header "  Select a profile:" \
  --cursor "  → " \
  --cursor.foreground 99 \
  --selected.foreground 212 \
  --height 10 \
  "${_profile_names[@]}")

load_profile "$PROFILE"
ok "$(gum style --foreground 212 --bold "$PROFILE_NAME")  $(gum style --faint "$GCP_INSTANCE_NAME")"

# ---------------------------------------------------------------------------
# Action selection
# ---------------------------------------------------------------------------
section "Action"

_action_line=$(gum choose \
  --header "  Select an action:" \
  --cursor "  → " \
  --cursor.foreground 99 \
  --selected.foreground 212 \
  --height 6 \
  "start       — Start VM and SSH in" \
  "stop        — Stop the VM" \
  "reset       — Wipe and recreate VM  ⚠  destructive" \
  "initialize  — First-time provision")

ACTION="${_action_line%%[[:space:]]*}"
ok "$(gum style --foreground 46 --bold "$ACTION")  $(gum style --faint "${_action_line#*— }")"

# ---------------------------------------------------------------------------
# Summary + confirm
# ---------------------------------------------------------------------------
echo
gum style \
  --border rounded \
  --padding "1 3" \
  --border-foreground 99 \
  "$(gum style --faint "Profile  ")   $(gum style --foreground 212 --bold "$PROFILE_NAME")" \
  "$(gum style --faint "VM       ")   $(gum style --foreground 244 "$GCP_INSTANCE_NAME")" \
  "$(gum style --faint "Region   ")   $(gum style --foreground 244 "$GCP_REGION")" \
  "$(gum style --faint "Action   ")   $(gum style --foreground 46  --bold "$ACTION")"
echo

if ! gum confirm \
    --prompt.foreground 212 \
    --selected.background 99 \
    "Run '$ACTION' on '$PROFILE_NAME'?"; then
  warn "Aborted."
  exit 0
fi

echo

# ---------------------------------------------------------------------------
# Execute — replace this process with the chosen script so its output,
# exit code, and any interactive prompts (e.g. reset's confirm) pass through.
# ---------------------------------------------------------------------------
case "$ACTION" in
  start)      exec "$SCRIPTS_DIR/start.sh"      --profile "$PROFILE" ;;
  stop)       exec "$SCRIPTS_DIR/stop.sh"       --profile "$PROFILE" ;;
  reset)      exec "$SCRIPTS_DIR/reset.sh"      --profile "$PROFILE" ;;
  initialize) exec "$SCRIPTS_DIR/initialize.sh" --profile "$PROFILE" ;;
  *)
    fail "Unknown action: $ACTION"
    exit 1
    ;;
esac
