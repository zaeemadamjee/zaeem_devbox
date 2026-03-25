#!/usr/bin/env bash
# welcome.sh — shown on every interactive SSH login.
# Sourced from ~/.zshrc (outside tmux only) and from the pre-bootstrap stub.
# WELCOME_SHOWN=1 is exported to prevent re-display after exec zsh.

export WELCOME_SHOWN=1

REPO="$HOME/zaeem_devbox"
PROFILE="${DEVBOX_PROFILE:-$(head -1 "$HOME/.config/devbox/profile" 2>/dev/null | tr -d '\r\n' || echo '?')}"
BOOTSTRAPPED=false
[[ -f "$HOME/.bootstrap-complete" ]] && BOOTSTRAPPED=true

# ---------------------------------------------------------------------------
# Machine info
# ---------------------------------------------------------------------------
_machine_os()     { lsb_release -ds 2>/dev/null || grep -oP '(?<=PRETTY_NAME=").*(?=")' /etc/os-release 2>/dev/null || uname -rs; }
_machine_cpu()    {
  local count model ghz
  count="$(nproc 2>/dev/null || echo '?')"
  model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || true)"
  ghz="$(echo "$model" | grep -oP '[\d.]+(?=GHz)' || true)"
  if [[ -n "$ghz" ]]; then echo "${count} vCPUs @ ${ghz}GHz"
  else echo "${count} vCPUs"; fi
}
_machine_mem()    { free -h 2>/dev/null | awk '/^Mem:/{print $2 " total, " $7 " available"}' || echo '?'; }
_machine_disk()   { df -h / 2>/dev/null | awk 'NR==2{print $3 " / " $2 " (" $5 " used)"}' || echo '?'; }
_machine_uptime() { uptime -p 2>/dev/null | sed 's/^up //' || echo '?'; }

SYS_OS="$(_machine_os)"
SYS_CPU="$(_machine_cpu)"
SYS_MEM="$(_machine_mem)"
SYS_DISK="$(_machine_disk)"
SYS_UPTIME="$(_machine_uptime)"

# ---------------------------------------------------------------------------
_run_bootstrap() {
  if bash "$REPO/dotfiles/bootstrap.sh"; then
    touch "$HOME/.bootstrap-complete"
    BOOTSTRAPPED=true
    echo ""
    exec zsh  # WELCOME_SHOWN=1 is exported, so the new shell skips the welcome screen
  fi
}

if ! command -v gum &>/dev/null; then
  echo ""
  echo "  ✗  gum is not installed — it should have been installed by Terraform's startup-script."
  echo "     Check /var/log/startup-script.log for errors."
  echo ""
  echo "     To install manually: sudo apt-get install -y gum"
  echo "     Then reconnect."
  echo ""
  return 1 2>/dev/null || exit 1
fi

# Build bootstrap status line
if $BOOTSTRAPPED; then
  _bootstrap_status="$(gum style --foreground 46 '✓ complete')"
else
  _bootstrap_status="$(gum style --foreground 202 '✗ not run')"
fi

echo
gum style \
  --border rounded \
  --border-foreground 99 \
  --padding "1 3" \
  --margin "0 1" \
  "$(gum style --bold --foreground 212 '⬡  zaeem devbox')" \
  "" \
  "Profile     $(gum style --foreground 99 "$PROFILE")" \
  "Bootstrap   $_bootstrap_status" \
  "" \
  "OS          $(gum style --foreground 244 "$SYS_OS")" \
  "CPU         $(gum style --foreground 244 "$SYS_CPU")" \
  "Memory      $(gum style --foreground 244 "$SYS_MEM")" \
  "Disk        $(gum style --foreground 244 "$SYS_DISK")" \
  "Uptime      $(gum style --foreground 244 "$SYS_UPTIME")"
echo

if ! $BOOTSTRAPPED; then
  if gum confirm --default=yes \
      --prompt.foreground 212 \
      --selected.background 99 \
      "Run bootstrap now?"; then
    echo
    _run_bootstrap
  else
    echo
    gum style --foreground 240 \
      "Run any time:      bootstrap" \
      "Check status only: bootstrap --check"
    echo
  fi
fi
