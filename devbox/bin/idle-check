#!/usr/bin/env bash
# idle-check.sh — Powers off the VM if idle for 30 minutes.
#
# "Idle" means: CPU load < 5% AND no active Claude Code or OpenCode process.
# Runs every 10 minutes via systemd timer (devbox-idle.timer).
# Logs to /var/log/idle-check.log

set -euo pipefail

IDLE_THRESHOLD_MINUTES=30
STATE_FILE="/tmp/last_active_time"
LOG="/var/log/idle-check.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# Check if Claude Code or OpenCode is running
if pgrep -f "claude-code\|@anthropic-ai\|opencode" &>/dev/null; then
  log "AI coding tool active — resetting idle timer"
  date +%s > "$STATE_FILE"
  exit 0
fi

# Check CPU usage (1-minute load average vs CPU count)
CPU_COUNT=$(nproc)
LOAD=$(awk '{print $1}' /proc/loadavg)
CPU_BUSY=$(awk -v avg="$LOAD" -v cpus="$CPU_COUNT" 'BEGIN { print (avg / cpus > 0.05) ? 1 : 0 }')

if [ "$CPU_BUSY" -eq 1 ]; then
  log "CPU busy (load=$LOAD) — resetting idle timer"
  date +%s > "$STATE_FILE"
  exit 0
fi

# Initialize state file if missing
if [ ! -f "$STATE_FILE" ]; then
  date +%s > "$STATE_FILE"
  exit 0
fi

LAST_ACTIVE=$(cat "$STATE_FILE")
NOW=$(date +%s)
IDLE_SECONDS=$((NOW - LAST_ACTIVE))
IDLE_MINUTES=$((IDLE_SECONDS / 60))

log "Idle for ${IDLE_MINUTES}m (threshold: ${IDLE_THRESHOLD_MINUTES}m)"

if [ "$IDLE_MINUTES" -ge "$IDLE_THRESHOLD_MINUTES" ]; then
  log "Idle threshold reached — shutting down"
  sudo poweroff || true
fi
