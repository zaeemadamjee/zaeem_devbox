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
# SSH_OPTS is populated lazily by _ssh_opts_init, called once before first use.
# This avoids expanding $SSH_KEY at source time (before bin/start sets it).
# - ConnectTimeout=10  : fail fast so retries kick in quickly
# - ServerAliveInterval/CountMax : detect dead connections within ~15 s
SSH_OPTS=()
_ssh_opts_init() {
  [[ ${#SSH_OPTS[@]} -gt 0 ]] && return 0
  SSH_OPTS=(
    -o StrictHostKeyChecking=no
    -o ConnectTimeout=10
    -o ServerAliveInterval=5
    -o ServerAliveCountMax=3
    -o BatchMode=yes
    -i "$SSH_KEY"
  )
}

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
  local max_s=150
  local elapsed=0

  # Phase 1: wait for external IP (up to 15 polls × 5 s = 75 s)
  local ip=""
  local i
  for i in $(seq 1 15); do
    log_progress_bar "$elapsed" "$max_s" "Waiting for SSH"
    ip=$(gcloud compute instances describe "$instance" \
      --zone="$zone" --project="$project" \
      --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || true)
    [[ -n "$ip" ]] && break
    sleep 5
    elapsed=$(( elapsed + 5 ))
  done

  if [[ -z "$ip" ]]; then
    log_progress_bar_clear
    return 1
  fi

  # Phase 2: wait for SSH (up to 30 polls × 5 s = 150 s, continuing elapsed)
  _ssh_opts_init
  for i in $(seq 1 30); do
    log_progress_bar "$elapsed" "$max_s" "Waiting for SSH"
    if ssh "${SSH_OPTS[@]}" "${user}@${ip}" true 2>/dev/null; then
      echo "$ip" > "$out"
      log_progress_bar_clear
      return 0
    fi
    sleep 5
    elapsed=$(( elapsed + 5 ))
  done

  log_progress_bar_clear
  return 1
}

# ---------------------------------------------------------------------------
# ssh_wait_startup <user> <ip>
#
# Waits up to 2.5 min for /var/lib/startup-complete to exist on the VM.
# Uses the ControlMaster if SSH_CONTROL_SOCKET is set and the socket exists;
# falls back to a direct connection using SSH_OPTS otherwise.
# Returns 0 when the marker is found, 1 on timeout.
# ---------------------------------------------------------------------------
ssh_wait_startup() {
  local user="$1" ip="$2"
  local i
  for i in $(seq 1 30); do
    if _ssh_run "$user" "$ip" "sudo test -f /var/lib/startup-complete" 2>/dev/null; then
      return 0
    fi
    sleep 5
  done
  return 1
}

# _ssh_run <user> <ip> <command>
# Internal helper: runs <command> via ControlMaster if available, direct otherwise.
_ssh_run() {
  local user="$1" ip="$2"
  shift 2
  if [[ -n "${SSH_CONTROL_SOCKET:-}" ]] && [[ -S "$SSH_CONTROL_SOCKET" ]]; then
    ssh -o ControlMaster=no -o "ControlPath=$SSH_CONTROL_SOCKET" \
      -o BatchMode=yes "${user}@${ip}" "$@"
  else
    _ssh_opts_init
    ssh "${SSH_OPTS[@]}" "${user}@${ip}" "$@"
  fi
}

# ---------------------------------------------------------------------------
# SSH ControlMaster lifecycle
#
# SSH_CONTROL_DIR  — temp directory holding the socket (set by ssh_master_open)
# SSH_CONTROL_SOCKET — path to the Unix socket
# ---------------------------------------------------------------------------

# ssh_master_open <user> <ip>
#
# Opens a background ControlMaster connection to <user>@<ip>.
# Sets SSH_CONTROL_DIR and SSH_CONTROL_SOCKET.
# Returns 0 on success, 1 if the master fails to start within 15 s.
ssh_master_open() {
  local user="$1" ip="$2"

  SSH_CONTROL_DIR=$(mktemp -d)
  SSH_CONTROL_SOCKET="${SSH_CONTROL_DIR}/master.sock"

  _ssh_opts_init
  # Open master in background with ControlPersist=no — the master exits
  # automatically once all slave connections have closed.
  ssh "${SSH_OPTS[@]}" \
    -o ControlMaster=yes \
    -o "ControlPath=$SSH_CONTROL_SOCKET" \
    -o ControlPersist=no \
    -N -f \
    "${user}@${ip}" || return 1

  # Wait up to 15 s for the socket to appear
  local i
  for i in $(seq 1 15); do
    [[ -S "$SSH_CONTROL_SOCKET" ]] && return 0
    sleep 1
  done

  return 1
}

# ssh_master_run <user> <ip> <command>
#
# Runs <command> on the VM over the ControlMaster connection.
# Requires SSH_CONTROL_SOCKET to be set and valid.
ssh_master_run() {
  local user="$1" ip="$2"
  shift 2
  ssh -o ControlMaster=no \
    -o "ControlPath=$SSH_CONTROL_SOCKET" \
    -o BatchMode=yes \
    "${user}@${ip}" "$@"
}

# ssh_master_pipe <user> <ip> <remote_command>
#
# Pipes stdin to <remote_command> on the VM over the ControlMaster connection.
# Use for file uploads: echo content | ssh_master_pipe user ip 'cat > file'
ssh_master_pipe() {
  local user="$1" ip="$2"
  shift 2
  ssh -o ControlMaster=no \
    -o "ControlPath=$SSH_CONTROL_SOCKET" \
    -o BatchMode=yes \
    "${user}@${ip}" "$@"
}

# ssh_master_close <user> <ip>
#
# Sends the exit control signal to the master, then removes the socket dir.
# Safe to call even if the master has already exited.
ssh_master_close() {
  local user="$1" ip="$2"
  ssh -o ControlMaster=no \
    -o "ControlPath=${SSH_CONTROL_SOCKET:-/dev/null}" \
    -o BatchMode=yes \
    -O exit \
    "${user}@${ip}" 2>/dev/null || true
  rm -rf "${SSH_CONTROL_DIR:-}"
}

# ---------------------------------------------------------------------------
# _diagnose_ssh_failure <instance> <zone> <project> <user>
#
# Prints a diagnostic summary when SSH fails: VM status, external IP,
# a quick SSH verbose probe, and the last 20 lines of the serial console.
# ---------------------------------------------------------------------------
_diagnose_ssh_failure() {
  local instance="$1" zone="$2" project="$3" user="$4"

  log_section "SSH Diagnostics"

  local status
  status=$(gcloud compute instances describe "$instance" \
    --zone="$zone" --project="$project" \
    --format="value(status)" 2>/dev/null || echo "unknown")
  if [[ "$status" == "RUNNING" ]]; then
    log_ok "VM status: RUNNING"
    log_dim "sshd not ready, wrong key, or firewall block"
  else
    log_warn "VM status: $status — expected RUNNING"
  fi

  local ip
  ip=$(gcloud compute instances describe "$instance" \
    --zone="$zone" --project="$project" \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || true)
  if [[ -z "$ip" ]]; then
    log_warn "No external IP — the VM has no natIP; check accessConfig in Terraform"
    return
  fi
  log_ok "External IP: $ip"

  log_warn "SSH connection attempt (verbose output):"
  echo
  ssh -vvv -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    -o BatchMode=yes -i "$SSH_KEY" "${user}@${ip}" true 2>&1 \
    | grep -E "(Connecting to|connect to address|Permission denied|Connection refused|Connection timed out|Received disconnect|Host key|debug1: Authentications)" \
    | head -15 \
    | while IFS= read -r line; do log_dim "$line"; done
  echo

  log_warn "Serial console — last 20 lines:"
  echo
  gcloud compute instances get-serial-port-output "$instance" \
    --zone="$zone" --project="$project" 2>/dev/null \
    | tail -20 \
    | while IFS= read -r line; do log_dim "$line"; done
  echo
}
