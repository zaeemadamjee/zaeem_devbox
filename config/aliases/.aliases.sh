# --- Aliases --- #
# --------------- #

# --- zshrc ---
alias szsh='source ~/.zshrc'

# --- ls ---
alias ls='eza -A'
alias ll='eza -lAh --git'

# --- cleanup ---
alias c='clear'

# --- git ---
alias gs='git status'
alias gst='git status'
alias gd='git diff'
alias gl='git log --oneline -20'
alias gcm='git commit -m'
alias gco='git checkout'
alias lg='lazygit'

# --- tmux ---
alias t="tmux new-session -A -s $(basename $(pwd))"
alias ta="tmux attach -t"
alias tls="tmux ls"
alias tk="tmux kill-session -t"
alias tr="tmux source-file ~/.tmux.conf"

# --- cd ---
alias ..='cd ..'
alias ...='cd ../..'

# --- claude ---
alias cc='claude'
alias ccd='claude --dangerously-skip-permissions'

# --- gcloud ---
alias gauth='gcloud auth login'