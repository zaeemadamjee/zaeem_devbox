#!/usr/bin/env bash
# bootstrap.sh — Set up dev box environment on a fresh Ubuntu 24.04 VM.
#
# Runs automatically via GCP startup-script on first boot.
# Can also be run manually:
#   git clone https://github.com/zaeemadamjee/zaeem_devbox.git ~/zaeem_devbox
#   bash ~/zaeem_devbox/dotfiles/bootstrap.sh
#
# Safe to re-run (idempotent).

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DOTFILES_DIR/.." && pwd)"

log() { echo "[bootstrap] $*"; }

# --- Install devbox (download binary directly — no interactive installer) ---
if ! command -v devbox &>/dev/null; then
  log "Installing devbox..."
  curl -fsSL https://releases.jetify.com/devbox -o /tmp/devbox
  sudo install -m 755 /tmp/devbox /usr/local/bin/devbox
  rm /tmp/devbox
fi

# --- Install devbox packages ---
log "Installing devbox global packages..."
devbox global pull "$REPO_ROOT/devbox/devbox.json"

# --- Symlink dotfiles ---
log "Symlinking dotfiles..."
ln -sf "$DOTFILES_DIR/zshrc"          "$HOME/.zshrc"
ln -sf "$DOTFILES_DIR/tmux.conf"      "$HOME/.tmux.conf"
ln -sf "$DOTFILES_DIR/gitconfig"      "$HOME/.gitconfig"
mkdir -p "$HOME/.config"
ln -sfT "$DOTFILES_DIR/nvim"          "$HOME/.config/nvim"
ln -sf "$DOTFILES_DIR/starship.toml"  "$HOME/.config/starship.toml"

# --- Set zsh as default shell ---
ZSH_PATH=$(command -v zsh)
if [ "$SHELL" != "$ZSH_PATH" ]; then
  log "Setting zsh as default shell..."
  grep -qxF "$ZSH_PATH" /etc/shells || echo "$ZSH_PATH" | sudo tee -a /etc/shells
  # Use usermod (works non-interactively); fall back to chsh for manual runs
  if sudo usermod -s "$ZSH_PATH" "$(whoami)" 2>/dev/null; then
    log "Shell set via usermod"
  else
    chsh -s "$ZSH_PATH"
  fi
fi

# --- Install TPM (tmux plugin manager) ---
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  log "Installing TPM..."
  git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi

# --- Symlink otelcol-contrib from devbox to /usr/local/bin ---
OTELCOL_SRC="$(devbox global path)/.devbox/nix/profile/default/bin/otelcol-contrib"
if [ -f "$OTELCOL_SRC" ]; then
  log "Symlinking otelcol-contrib to /usr/local/bin..."
  sudo ln -sf "$OTELCOL_SRC" /usr/local/bin/otelcol-contrib
fi

# --- Install otelcol-contrib systemd service ---
if [ -f "$DOTFILES_DIR/otelcol-contrib.service" ]; then
  log "Installing otelcol-contrib service..."
  sudo mkdir -p /etc/otelcol-contrib
  sudo cp "$DOTFILES_DIR/otelcol-contrib-config.yaml" /etc/otelcol-contrib/config.yaml
  sudo cp "$DOTFILES_DIR/otelcol-contrib.service" /etc/systemd/system/otelcol-contrib.service
  sudo systemctl daemon-reload
  sudo systemctl enable --now otelcol-contrib
  log "otelcol-contrib service enabled"
fi

# --- Seed tealdeer page cache ---
tldr --update || true

# --- Import shell history into atuin ---
atuin import auto || true

# --- Install Claude Code (native installer, auto-updates) ---
if ! command -v claude &>/dev/null; then
  log "Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
fi

# --- Install opencode ---
if ! command -v opencode &>/dev/null; then
  log "Installing opencode..."
  curl -fsSL https://opencode.ai/install | bash
fi

# --- Install systemd idle timer (added in next step) ---
if [ -f "$DOTFILES_DIR/idle-check.sh" ]; then
  log "Installing idle-stop timer..."
  sudo cp "$DOTFILES_DIR/idle-check.sh" /usr/local/bin/idle-check.sh
  sudo chmod +x /usr/local/bin/idle-check.sh
  sudo cp "$DOTFILES_DIR/devbox-idle.service" /etc/systemd/system/devbox-idle.service
  sudo cp "$DOTFILES_DIR/devbox-idle.timer"   /etc/systemd/system/devbox-idle.timer
  sudo systemctl daemon-reload
  sudo systemctl enable --now devbox-idle.timer
  log "Idle timer enabled (30min threshold, checks every 10min)"
fi

log ""
log "Bootstrap complete!"
log "Log out and back in for shell change to take effect."
log "You will auto-attach to a tmux session named 'main' on login."
