#!/usr/bin/env bash
#
# lib/banner.sh — ASCII art banner utility.
#
# Usage: source this file, then call: print_banner [label]
#   label — text shown on the monitor base (max ~20 chars). Default: empty.
#

# TTY color detection (mirrors lib/log.sh pattern)
if [[ -t 1 ]]; then
  _BANNER_COLOR='\033[2;36m'  # dim cyan
  _BANNER_RESET='\033[0m'
else
  _BANNER_COLOR=''
  _BANNER_RESET=''
fi

# Centre $1 in a field of $2 chars, padding with spaces.
_banner_centre() {
  local text="$1" width="$2"
  local len=${#text}
  local total_pad=$(( width - len ))
  local left_pad=$(( total_pad / 2 ))
  local right_pad=$(( total_pad - left_pad ))
  printf "%${left_pad}s%s%${right_pad}s" "" "$text" ""
}

print_banner() {
  local label
  label="$(_banner_centre "${1:-}" 25)"

  local lines=(
    "     ___________"
    "    / ========= \\"
    "   / ___________ \\"
    "  | _____________ |"
    "  | | >za       | |"
    "  | |           | |"
    "  | |___________| |________________________"
    "  \\=_____________/${label})"
    "  / \"\"\"\"\"\"\"\"\"\"\"\"\" \\                       /"
    " / ::::::::::::::: \\                  =D-'"
    "(___________________)"
  )

  echo ""
  for line in "${lines[@]}"; do
    printf "${_BANNER_COLOR}%s${_BANNER_RESET}\n" "$line"
    sleep 0.03
  done
  echo ""
}
