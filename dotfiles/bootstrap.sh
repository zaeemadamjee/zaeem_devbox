#!/usr/bin/env bash
# bootstrap.sh — Set up dev box environment on a Terraform-provisioned Ubuntu 24.04 VM.
#
# Run manually after first login (profile is required — no default):
#   export DEVBOX_PROFILE=personal   # or: echo personal > ~/.config/devbox/profile
#   bash ~/zaeem_devbox/dotfiles/bootstrap.sh [--check]
#
# --check   Print status of every component without installing anything.
# (no flag)  Install or repair anything that is missing.
#
# Safe to re-run (idempotent).
#
# Note: git, curl, zsh, gum, and default shell are guaranteed by Terraform's
# startup-script and do not need to be managed here.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DOTFILES_DIR/.." && pwd)"

# Export so install bodies can access them when run in bash -c subshells via gum spin.
export DOTFILES_DIR REPO_ROOT

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
CHECK_ONLY=false
for arg in "$@"; do
  [[ "$arg" == "--check" ]] && CHECK_ONLY=true
done

# ---------------------------------------------------------------------------
# Output helpers + timing
# ---------------------------------------------------------------------------
GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; CYAN="\033[36m"; DIM="\033[2m"; RESET="\033[0m"

if ! command -v gum &>/dev/null; then
  echo ""
  echo "  ✗  gum is not installed — it should have been installed by Terraform's startup-script."
  echo "     Check /var/log/startup-script.log for errors."
  echo ""
  echo "     To install manually: sudo apt-get install -y gum"
  echo "     Then re-run bootstrap."
  echo ""
  exit 1
fi

# Millisecond timestamp (falls back to seconds on systems without %3N).
_t0()      { date +%s%3N 2>/dev/null || date +%s; }
_elapsed() {
  local d=$(( $(_t0) - $1 ))
  (( d < 1000 )) && { echo "${d}ms"; return; }
  echo "$(( d / 1000 )).$(( (d % 1000) / 100 ))s"
}

BOOTSTRAP_T0=$(_t0)

section() { echo; gum style --bold --foreground 99 "  ▸  $*"; echo; }
ok()      { printf "  ${GREEN}✓${RESET}  %s\n" "$*"; }
skip()    { printf "  ${GREEN}✓${RESET}  ${DIM}%s (already installed)${RESET}\n" "$*"; }
warn()    { printf "  ${YELLOW}⚠${RESET}  %s\n" "$*"; }
fail()    { printf "  ${RED}✗${RESET}  %s\n" "$*"; }

# timed_spin [--show-output] <title> <cmd> [args...]
# Runs cmd under a gum spinner and prints ✓ with elapsed time when done.
# Use --show-output for commands whose live output is informative (e.g. devbox pull).
timed_spin() {
  local show_output=""
  [[ "${1:-}" == "--show-output" ]] && { show_output="--show-output"; shift; }
  local title="$1"; shift
  local t0; t0=$(_t0)
  # shellcheck disable=SC2086
  gum spin $show_output --spinner dot --title "  ${title}..." -- "$@"
  ok "${title}  $(gum style --faint "$(_elapsed "$t0")")"
}

MISSING=()
track_missing() { MISSING+=("$1"); }

# step <label> <check_expr> <install_body>
#   check_expr   — bash expression evaluated in current shell; exit 0 = already done
#   install_body — shell command string run via gum spin (subprocess); skipped in --check mode
step() {
  local label="$1" check="$2" install="$3"
  if eval "$check" &>/dev/null 2>&1; then
    skip "$label"
  elif $CHECK_ONLY; then
    fail "$label"
    track_missing "$label"
  else
    local t0; t0=$(_t0)
    gum spin --spinner dot --title "  ${label}..." -- bash -c "$install"
    ok "${label}  $(gum style --faint "$(_elapsed "$t0")")"
  fi
}

# ---------------------------------------------------------------------------
# Profile resolution (required — no default)
# ---------------------------------------------------------------------------
section "Profile"
DEVBOX_PROFILE="${DEVBOX_PROFILE:-}"
if [[ -z "$DEVBOX_PROFILE" ]] && [[ -f "$HOME/.config/devbox/profile" ]]; then
  DEVBOX_PROFILE="$(head -1 "$HOME/.config/devbox/profile" | tr -d '\r\n')"
fi
DEVBOX_PROFILE="${DEVBOX_PROFILE#"${DEVBOX_PROFILE%%[![:space:]]*}"}"
DEVBOX_PROFILE="${DEVBOX_PROFILE%"${DEVBOX_PROFILE##*[![:space:]]}"}"
if [[ -z "${DEVBOX_PROFILE// }" ]]; then
  fail "DEVBOX_PROFILE is not set"
  echo "       Export DEVBOX_PROFILE=<name> or write one line to ~/.config/devbox/profile"
  exit 1
fi
case "$DEVBOX_PROFILE" in
  */*|*..*|\ *) fail "Invalid DEVBOX_PROFILE '${DEVBOX_PROFILE}' (no slashes, .., or spaces)"; exit 1 ;;
esac
PROFILE_SCRIPT="$REPO_ROOT/scripts/profiles/${DEVBOX_PROFILE}.sh"
if [[ ! -f "$PROFILE_SCRIPT" ]]; then
  fail "Profile script not found: ${PROFILE_SCRIPT}"
  exit 1
fi
IDLE_TIMER_ENABLED=true
# shellcheck source=/dev/null
source "$PROFILE_SCRIPT"
ok "Profile: ${DEVBOX_PROFILE}"

idle_timer_enabled_bool() {
  case "${IDLE_TIMER_ENABLED:-true}" in
    false|False|FALSE|0|no|No|off|Off) return 1 ;;
    *) return 0 ;;
  esac
}

# ---------------------------------------------------------------------------
# devbox
# ---------------------------------------------------------------------------
section "devbox"
step "devbox binary" \
  "command -v devbox" \
  "curl -fsSL https://releases.jetify.com/devbox -o /tmp/devbox && sudo install -m 755 /tmp/devbox /usr/local/bin/devbox && rm /tmp/devbox"

if ! $CHECK_ONLY; then
  # --show-output so the user can see which packages are being pulled
  timed_spin --show-output "Pulling devbox global packages" \
    devbox global pull "$REPO_ROOT/devbox/devbox.json"
  eval "$(devbox global shellenv)"
else
  step "devbox global packages synced" \
    "devbox global list 2>/dev/null | grep -q ." \
    ""
fi

# ---------------------------------------------------------------------------
# Shell
# ---------------------------------------------------------------------------
section "Shell"

step "tmux plugin manager (TPM)" \
  "test -d \$HOME/.tmux/plugins/tpm" \
  "git clone https://github.com/tmux-plugins/tpm \$HOME/.tmux/plugins/tpm"

# ---------------------------------------------------------------------------
# Dotfiles
# ---------------------------------------------------------------------------
section "Dotfiles"

_link_check() {
  local src="$1" dst="$2"
  [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == "$src" ]]
}

symlink_step() {
  local label="$1" src="$2" dst="$3" flag="${4:-}"
  local install_cmd
  if [[ "$flag" == "-T" ]]; then
    install_cmd="ln -sfT '$src' '$dst'"
  else
    install_cmd="ln -sf '$src' '$dst'"
  fi
  step "$label" "_link_check '$src' '$dst'" "$install_cmd"
}

if ! $CHECK_ONLY; then
  mkdir -p "$HOME/.config" "$HOME/.config/opencode"
fi

symlink_step "~/.zshrc"                          "$DOTFILES_DIR/zshrc"                        "$HOME/.zshrc"
symlink_step "~/.aliases.sh"                     "$DOTFILES_DIR/aliases.sh"                   "$HOME/.aliases.sh"
symlink_step "~/.tmux.conf"                      "$DOTFILES_DIR/tmux.conf"                    "$HOME/.tmux.conf"
symlink_step "~/.gitconfig"                      "$DOTFILES_DIR/gitconfig"                    "$HOME/.gitconfig"
symlink_step "~/.config/nvim"                    "$DOTFILES_DIR/nvim"                         "$HOME/.config/nvim" "-T"
symlink_step "~/.config/starship.toml"           "$DOTFILES_DIR/starship.toml"                "$HOME/.config/starship.toml"
symlink_step "~/.config/opencode/opencode.json"  "$DOTFILES_DIR/opencode/opencode.json"       "$HOME/.config/opencode/opencode.json"

# ---------------------------------------------------------------------------
# Observability (otelcol-contrib)
# ---------------------------------------------------------------------------
section "Observability"
OTELCOL_SRC="$(devbox global path 2>/dev/null)/.devbox/nix/profile/default/bin/otelcol-contrib"
export OTELCOL_SRC

step "otelcol-contrib binary" \
  "command -v otelcol-contrib" \
  "[[ -f \"\$OTELCOL_SRC\" ]] && sudo ln -sf \"\$OTELCOL_SRC\" /usr/local/bin/otelcol-contrib || echo '  ⚠  otelcol-contrib not found in devbox — is it in devbox.json?'"

step "otelcol-contrib systemd service" \
  "systemctl is-enabled otelcol-contrib &>/dev/null" \
  "sudo mkdir -p /etc/otelcol-contrib && sudo cp \"\$DOTFILES_DIR/otelcol-contrib-config.yaml\" /etc/otelcol-contrib/config.yaml && sudo cp \"\$DOTFILES_DIR/otelcol-contrib.service\" /etc/systemd/system/otelcol-contrib.service && sudo systemctl daemon-reload && sudo systemctl enable --now otelcol-contrib"

# ---------------------------------------------------------------------------
# Idle timer
# ---------------------------------------------------------------------------
section "Idle timer"
if idle_timer_enabled_bool; then
  step "devbox-idle systemd timer" \
    "systemctl is-enabled devbox-idle.timer &>/dev/null" \
    "sudo cp \"\$DOTFILES_DIR/idle-check.sh\" /usr/local/bin/idle-check.sh && sudo chmod +x /usr/local/bin/idle-check.sh && sudo cp \"\$DOTFILES_DIR/devbox-idle.service\" /etc/systemd/system/devbox-idle.service && sudo cp \"\$DOTFILES_DIR/devbox-idle.timer\" /etc/systemd/system/devbox-idle.timer && sudo systemctl daemon-reload && sudo systemctl enable --now devbox-idle.timer"
else
  if systemctl is-enabled devbox-idle.timer &>/dev/null; then
    if $CHECK_ONLY; then
      warn "devbox-idle timer is running but IDLE_TIMER_ENABLED=false in profile"
    else
      gum spin --spinner dot --title "  Removing idle timer (disabled in profile)..." -- \
        bash -c "sudo systemctl stop devbox-idle.timer 2>/dev/null; sudo systemctl disable devbox-idle.timer 2>/dev/null; sudo rm -f /etc/systemd/system/devbox-idle.timer /etc/systemd/system/devbox-idle.service /usr/local/bin/idle-check.sh; sudo systemctl daemon-reload; sudo systemctl reset-failed 2>/dev/null || true"
      ok "idle timer removed"
    fi
  else
    skip "idle timer (disabled in profile)"
  fi
fi

# ---------------------------------------------------------------------------
# CLI tools
# ---------------------------------------------------------------------------
section "CLI tools"
step "Claude Code (claude)" \
  "command -v claude" \
  "curl -fsSL https://claude.ai/install.sh | bash"

step "opencode" \
  "command -v opencode" \
  "curl -fsSL https://opencode.ai/install | bash"

if ! $CHECK_ONLY; then
  timed_spin "Seeding tealdeer page cache" bash -c 'tldr --update >/dev/null 2>&1 || true'
  timed_spin "Importing atuin history"     bash -c 'atuin import auto 2>/dev/null || true'
fi

# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------
section "Secrets"
if [[ -s "$HOME/.config/secrets.env" ]]; then
  mapfile -t _SECRET_VARS < <(grep -oP '^(export\s+)?\K[A-Z_][A-Z0-9_]+(?==)' "$HOME/.config/secrets.env" 2>/dev/null || true)
  ok "~/.config/secrets.env (${#_SECRET_VARS[@]} vars)"
  for _var in "${_SECRET_VARS[@]}"; do
    printf "  $(gum style --foreground 240 '  ·  %s')\n" "$_var"
  done
else
  if $CHECK_ONLY; then
    fail "~/.config/secrets.env (missing or empty — run start.sh to copy your .env file)"
    track_missing "secrets"
  else
    warn "~/.config/secrets.env not found — run start.sh to copy your profile .env file"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL_ELAPSED=$(_elapsed "$BOOTSTRAP_T0")

if $CHECK_ONLY; then
  if [[ ${#MISSING[@]} -eq 0 ]]; then
    echo
    gum style --border rounded --padding "1 2" --border-foreground 46 \
      "$(gum style --foreground 46 --bold '✓  All components installed')"
    echo
  else
    echo
    gum style --border rounded --padding "1 2" --border-foreground 202 \
      "$(gum style --foreground 202 --bold "✗  ${#MISSING[@]} component(s) missing:")" \
      "" \
      "$(printf '  %s\n' "${MISSING[@]}")" \
      "" \
      "$(gum style --foreground 240 'Run bootstrap without --check to install.')"
    echo
    exit 1
  fi
else
  echo
  gum style --border rounded --padding "1 2" --border-foreground 46 \
    "$(gum style --foreground 46 --bold '✓  Bootstrap complete')" \
    "" \
    "$(gum style --foreground 240 "Completed in ${TOTAL_ELAPSED}.")" \
    "$(gum style --foreground 240 'Log out and back in for shell changes to take effect.')" \
    "$(gum style --foreground 240 "You will auto-attach to a tmux session named 'main' on login.")"
  echo
fi
