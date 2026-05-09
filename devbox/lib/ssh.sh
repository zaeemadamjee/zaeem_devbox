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
