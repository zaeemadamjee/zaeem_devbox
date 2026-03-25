#!/usr/bin/env bash
# lib/ui.sh — Shared gum-based output helpers for local devbox scripts.
#
# Source this after lib/profile.sh, then call require_gum early:
#   source "$SCRIPTS_DIR/lib/profile.sh"
#   source "$SCRIPTS_DIR/lib/ui.sh"
#   require_gum

# Exits with a clear message if gum is not installed locally.
require_gum() {
  if ! command -v gum &>/dev/null; then
    echo "  Error: gum is required locally. Install with: brew install gum"
    exit 1
  fi
}

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

section() { echo; gum style --bold --foreground 99 "  ▸  $*"; echo; }
ok()      { printf "  ${GREEN}✓${RESET}  %s\n" "$*"; }
warn()    { printf "  ${YELLOW}⚠${RESET}  %s\n" "$*"; }
fail()    { printf "  ${RED}✗${RESET}  %s\n" "$*" >&2; }
skip()    { printf "  ${GREEN}✓${RESET}  \033[2m%s\033[0m\n" "$*"; }
