#!/usr/bin/env bash
# devbox/lib/ssh.sh — SSH primitives for devbox scripts.
#
# Source this file after lib/profile:
#   source "$BIN_DIR/../lib/ssh.sh"
#
# Requires: SSH_KEY and SSH_USER to be set by the caller (bin/start sets these).

# ---------------------------------------------------------------------------
# Shared SSH options
# ---------------------------------------------------------------------------
# - ConnectTimeout=10  : fail fast so retries kick in quickly
# - ServerAliveInterval/CountMax : detect dead connections within ~15 s
SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o ConnectTimeout=10
  -o ServerAliveInterval=5
  -o ServerAliveCountMax=3
  -o BatchMode=yes
  -i "$SSH_KEY"
)

# ---------------------------------------------------------------------------
# ssh_retry <max_attempts> <delay_s> <command> [args...]
#
# Retries the given command up to <max_attempts> times with <delay_s> seconds
# between attempts. Returns 0 on first success, 1 after all attempts fail.
# ---------------------------------------------------------------------------
ssh_retry() {
  local attempts="$1" delay="$2"
  shift 2
  local i
  for i in $(seq 1 "$attempts"); do
    if "$@"; then
      return 0
    fi
    if [[ "$i" -lt "$attempts" ]]; then
      sleep "$delay"
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# ssh_wait_ready <instance> <zone> <project> <user> <out_file>
#
# Waits up to 2.5 min for the VM to have an external IP AND accept SSH.
# Phase 1: polls gcloud until natIP is non-empty (up to 15 attempts, 5 s apart).
# Phase 2: polls SSH until a test connection succeeds (up to 30 attempts, 5 s apart).
# On success, writes the IP to <out_file> and returns 0.
# Returns 1 on timeout.
# ---------------------------------------------------------------------------
ssh_wait_ready() {
  local instance="$1" zone="$2" project="$3" user="$4" out="$5"

  # Phase 1: wait for external IP
  local ip=""
  local i
  for i in $(seq 1 15); do
    ip=$(gcloud compute instances describe "$instance" \
      --zone="$zone" --project="$project" \
      --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || true)
    [[ -n "$ip" ]] && break
    sleep 5
  done

  if [[ -z "$ip" ]]; then
    return 1
  fi

  # Phase 2: wait for SSH
  for i in $(seq 1 30); do
    if ssh "${SSH_OPTS[@]}" "${user}@${ip}" true 2>/dev/null; then
      echo "$ip" > "$out"
      return 0
    fi
    sleep 5
  done

  return 1
}
