#!/usr/bin/env bash
# welcome.sh — shown on first login via stub ~/.zshrc until bootstrap completes.
# Safe to re-run; exits immediately once bootstrap is complete.

# Belt-and-suspenders check in case of manual invocation after bootstrap:
[[ -f "$HOME/.bootstrap-complete" ]] && return 0 2>/dev/null || exit 0

REPO="$HOME/zaeem_devbox"
PROFILE="${DEVBOX_PROFILE:-$(head -1 "$HOME/.config/devbox/profile" 2>/dev/null | tr -d '\r\n' || echo '?')}"

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
    echo ""
    exec zsh
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

echo
gum style \
  --border rounded \
  --border-foreground 99 \
  --padding "1 3" \
  --margin "0 1" \
  "$(gum style --bold --foreground 212 '⬡  zaeem devbox')" \
  "" \
  "Profile   $(gum style --foreground 99 "$PROFILE")" \
  "Repo      $(gum style --foreground 240 "$REPO")" \
  "" \
  "OS        $(gum style --foreground 244 "$SYS_OS")" \
  "CPU       $(gum style --foreground 244 "$SYS_CPU")" \
  "Memory    $(gum style --foreground 244 "$SYS_MEM")" \
  "Disk      $(gum style --foreground 244 "$SYS_DISK")" \
  "Uptime    $(gum style --foreground 244 "$SYS_UPTIME")" \
  "" \
  "$(gum style --foreground 240 'Run bootstrap to install tools, dotfiles, and shell config.')" \
  "$(gum style --foreground 240 'Safe to run again at any time.')"
echo

if gum confirm --default=yes \
    --prompt.foreground 212 \
    --selected.background 99 \
    "Run bootstrap now?"; then
  echo
  _run_bootstrap
else
  echo
  gum style --foreground 240 \
    "Run any time:" \
    "  bash ~/zaeem_devbox/dotfiles/bootstrap.sh" \
    "" \
    "Check status only:" \
    "  bash ~/zaeem_devbox/dotfiles/bootstrap.sh --check"
  echo
fi
