# --- PATH: tool install dirs (must come before welcome so bootstrap --check finds them) ---
export PATH="$HOME/.local/bin:$PATH"           # claude code
export PATH="$HOME/.opencode/bin:$PATH"        # opencode
export PATH="$HOME/.npm-global/bin:$PATH"      # npm globals
export PATH="$HOME/.cargo/bin:$PATH"           # rust/cargo
export PATH="$PATH:$HOME/go/bin"               # go workspace binaries

# --- SSH agent forwarding (stable socket so tmux panes stay connected) ---
# Must run before tmux attach so the symlink is fresh when we re-enter an existing session.
if [[ -n "$SSH_AUTH_SOCK" && "$SSH_AUTH_SOCK" != "$HOME/.ssh/agent.sock" ]]; then
  ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/agent.sock"
fi
export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"

# --- Welcome screen + tmux attach (SSH login only, not already inside tmux) ---
# Placed early so exec tmux short-circuits the rest of zshrc on initial SSH login —
# devbox/starship/etc only need to init inside tmux sessions, not the throwaway
# pre-tmux shell. PATH is set above so bootstrap --check can find all tools.
if [[ -n "$SSH_CONNECTION" ]] && [[ -z "$TMUX" ]] && [[ -t 0 ]]; then
  if [[ -z "${WELCOME_SHOWN:-}" ]]; then
    [[ -f "$HOME/zaeem_devbox/devbox/bin/welcome" ]] && source "$HOME/zaeem_devbox/devbox/bin/welcome"
  else
    exec tmux new-session -A -s main
  fi
fi

# --- History ---
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history
setopt HIST_IGNORE_DUPS
setopt SHARE_HISTORY
setopt HIST_VERIFY

# --- Options ---
setopt AUTO_CD
setopt CORRECT

# --- Aliases ---
source ~/.aliases.sh
alias bootstrap='bash ~/zaeem_devbox/devbox/bin/bootstrap'

# --- Homebrew (manages python, go, rust, etc.) ---
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
[[ -f "${BREW_PREFIX}/bin/brew" ]] && eval "$("${BREW_PREFIX}/bin/brew" shellenv)"
# rustup is keg-only — add to PATH explicitly
[[ -d "${BREW_PREFIX}/opt/rustup/bin" ]] && export PATH="${BREW_PREFIX}/opt/rustup/bin:$PATH"

# --- nvm (Node version manager — installed via Homebrew) ---
export NVM_DIR="$HOME/.nvm"
[[ -s "${BREW_PREFIX}/opt/nvm/nvm.sh" ]] && source "${BREW_PREFIX}/opt/nvm/nvm.sh"
[[ -s "${BREW_PREFIX}/opt/nvm/etc/bash_completion.d/nvm" ]] && source "${BREW_PREFIX}/opt/nvm/etc/bash_completion.d/nvm"

# --- Prompt (after Homebrew so starship is in PATH) ---
eval "$(starship init zsh)"


# --- Secrets (copied from local devbox/profiles/<name>.env by bin/start) ---
# set -a auto-exports every variable defined during the source so subprocesses
# (opencode, claude, etc.) inherit them without needing explicit `export` in the file.
if [ -f "$HOME/.config/secrets.env" ]; then
  set -a
  source "$HOME/.config/secrets.env"
  set +a
fi

# --- Rust/cargo (env sets CARGO_HOME etc, PATH already includes ~/.cargo/bin above) ---
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

# --- fzf ---
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# --- zoxide (smart cd) ---
eval "$(zoxide init zsh)"

# --- atuin (shell history) ---
command -v atuin &>/dev/null && eval "$(atuin init zsh)"

# opencode
export PATH="$HOME/.opencode/bin:$PATH"
