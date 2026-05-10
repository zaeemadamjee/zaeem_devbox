#!/usr/bin/env bash
#
# Minimal logging library for clean, informative output
#

# Colors (with TTY detection for fallback)
if [[ -t 1 ]]; then
  _LOG_GREEN='\033[32m'
  _LOG_RED='\033[31m'
  _LOG_YELLOW='\033[33m'
  _LOG_DIM='\033[2m'
  _LOG_RESET='\033[0m'
else
  _LOG_GREEN=''
  _LOG_RED=''
  _LOG_YELLOW=''
  _LOG_DIM=''
  _LOG_RESET=''
fi

# Clean section divider for start/end
log_banner() {
  echo ""
  echo "─── $1 ───"
  echo ""
}

# Major step (▸ prefix, blank line before)
log_section() {
  echo ""
  echo "▸ $1"
}

# Sub-step (indented)
log_info() {
  echo "  $1"
}

# Success (✓ prefix, indented, green)
log_ok() {
  if [[ -t 1 ]]; then
    printf "\r  ${_LOG_GREEN}✓${_LOG_RESET} %s\n" "$1"
  else
    echo -e "  ${_LOG_GREEN}✓${_LOG_RESET} $1"
  fi
}

# Error (✗ prefix, indented, red, stderr)
log_error() {
  if [[ -t 2 ]]; then
    printf "\r  ${_LOG_RED}✗${_LOG_RESET} %s\n" "$1" >&2
  else
    echo -e "  ${_LOG_RED}✗${_LOG_RESET} $1" >&2
  fi
}

# Warning (! prefix, indented, yellow)
log_warn() {
  echo -e "  ${_LOG_YELLOW}!${_LOG_RESET} $1"
}

# Secondary info (dim gray, indented)
log_dim() {
  echo -e "  ${_LOG_DIM}$1${_LOG_RESET}"
}

# Pending step (· prefix, no newline on TTY — overwrite with log_ok/log_error to replace in-place)
log_pending() {
  if [[ -t 1 ]]; then
    printf "  ${_LOG_DIM}·${_LOG_RESET} %s" "$*"
  else
    echo "  · $*"
  fi
}

# Progress bar — renders/updates in-place using \r.
# Usage: log_progress_bar <elapsed_s> <max_s> <label>
#
# On a TTY: overwrites the current line each call. Call log_progress_bar_clear
# before printing a log_ok/log_error so the bar line is fully erased.
# Off-TTY (pipe/CI): prints a single plain line on the first call, then no-ops.
_LOG_PROGRESS_PRINTED=0
log_progress_bar() {
  local elapsed="$1" max="$2" label="$3"
  local width=20

  # Compute fill (integer arithmetic; cap at width)
  local fill=$(( elapsed * width / (max > 0 ? max : 1) ))
  (( fill > width )) && fill=$width
  local empty=$(( width - fill ))

  local bar_filled="" bar_empty=""
  local i
  for (( i=0; i<fill; i++ )); do bar_filled+="█"; done
  for (( i=0; i<empty; i++ )); do bar_empty+="░"; done

  # Elapsed / max display (show as integers)
  local time_str="${elapsed}s / ${max}s"

  if [[ -t 1 ]]; then
    # TTY: overwrite the current line
    printf "\r  ${_LOG_DIM}·${_LOG_RESET} %-28s ${_LOG_DIM}[${_LOG_RESET}${_LOG_GREEN}%s${_LOG_RESET}${_LOG_DIM}%s]${_LOG_RESET} %s   " \
      "$label" "$bar_filled" "$bar_empty" "$time_str"
  else
    # Non-TTY: print once, then silence
    if [[ "$_LOG_PROGRESS_PRINTED" -eq 0 ]]; then
      printf "  · %s [%s%s] %s\n" "$label" "$bar_filled" "$bar_empty" "$time_str"
      _LOG_PROGRESS_PRINTED=1
    fi
  fi
}

# Clears the progress bar line (TTY only) so the next log_ok/log_error
# lands on a clean line. Also resets the non-TTY print-once guard so a
# subsequent wait loop will print its initial line.
log_progress_bar_clear() {
  if [[ -t 1 ]]; then
    printf "\r%-80s\r" ""
  fi
  _LOG_PROGRESS_PRINTED=0
}
