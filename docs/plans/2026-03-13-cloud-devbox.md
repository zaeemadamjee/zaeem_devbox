# Cloud Dev Box Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Provision a GCP Compute Engine VM managed by Terraform, with a full devbox-managed dev environment, tmux session persistence, auto-stop on idle, and cost guardrails.

**Architecture:** Terraform declares all GCP resources (VM, firewall, GCS state bucket). devbox pins all dev tools declaratively. Dotfiles are committed to this repo and symlinked into $HOME on the VM via bootstrap.sh. A systemd idle timer powers off the VM after 30 minutes of inactivity.

**Tech Stack:** Terraform, GCP (Compute Engine, GCS), devbox, Ubuntu 24.04, zsh, tmux, systemd

---

## Prerequisites (do these before running any tasks)

- `gcloud` CLI installed and authenticated locally (`gcloud auth login`)
- Terraform installed locally (`brew install terraform`)
- devbox installed locally (`curl -fsSL https://get.jetpack.io/devbox | bash`)
- A GCP project already exists — note its project ID
- You have Owner or Editor role on the GCP project

---

### Task 1: Enable GCP APIs and create SSH key

**Files:**
- No code files — gcloud commands only

**Step 1: Enable required GCP APIs**

```bash
gcloud services enable compute.googleapis.com storage.googleapis.com \
  --project=YOUR_PROJECT_ID
```

Expected: `Operation finished successfully.`

**Step 2: Generate SSH key pair for the dev box**

```bash
ssh-keygen -t ed25519 -C "zaeem-devbox" -f ~/.ssh/zaeem_devbox
```

Expected: Creates `~/.ssh/zaeem_devbox` (private) and `~/.ssh/zaeem_devbox.pub` (public).

**Step 3: Note your public key**

```bash
cat ~/.ssh/zaeem_devbox.pub
```

Copy the output — you'll need it in Task 3.

**Step 4: Commit**

```bash
git commit --allow-empty -m "chore: confirmed GCP APIs enabled and SSH key generated"
```

---

### Task 2: Bootstrap GCS state bucket

The Terraform state bucket must exist before Terraform can use it as a backend — it can't create its own state store.

**Files:**
- No code files — gcloud commands only

**Step 1: Create the GCS bucket**

```bash
gcloud storage buckets create gs://zaeem-tf-state \
  --project=YOUR_PROJECT_ID \
  --location=US \
  --uniform-bucket-level-access
```

Expected: `Creating gs://zaeem-tf-state/...`

> If the name is taken (GCS buckets are globally unique), try `zaeem-tf-state-YOURNAME`.

**Step 2: Enable versioning (protects state history)**

```bash
gcloud storage buckets update gs://zaeem-tf-state --versioning
```

Expected: `Updating gs://zaeem-tf-state/...`

**Step 3: Commit**

```bash
git commit --allow-empty -m "chore: GCS state bucket created"
```

---

### Task 3: Terraform directory structure and provider config

**Files:**
- Create: `terraform/main.tf`
- Create: `terraform/variables.tf`
- Create: `terraform/outputs.tf`
- Create: `terraform/.gitignore`

**Step 1: Create `terraform/.gitignore`**

```
.terraform/
*.tfstate
*.tfstate.backup
*.tfvars
.terraform.lock.hcl
```

> `.tfvars` files often contain secrets — never commit them.

**Step 2: Create `terraform/variables.tf`**

```hcl
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access (contents of ~/.ssh/zaeem_devbox.pub)"
  type        = string
}
```

**Step 3: Create `terraform/main.tf` (provider + backend only for now)**

```hcl
terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "zaeem-tf-state"
    prefix = "devbox"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
```

**Step 4: Create `terraform/outputs.tf`**

```hcl
output "instance_name" {
  description = "VM instance name"
  value       = google_compute_instance.devbox.name
}

output "external_ip" {
  description = "Current ephemeral external IP (only valid when running)"
  value       = google_compute_instance.devbox.network_interface[0].access_config[0].nat_ip
}
```

**Step 5: Create `terraform/terraform.tfvars.example`**

```hcl
project_id     = "your-gcp-project-id"
ssh_public_key = "ssh-ed25519 AAAA... zaeem_devbox"
```

> Copy this to `terraform.tfvars` (gitignored) and fill in real values before running Terraform.

**Step 6: Initialize Terraform**

```bash
cd terraform
terraform init
```

Expected: `Terraform has been successfully initialized!`

**Step 7: Commit**

```bash
git add terraform/
git commit -m "feat: add Terraform provider config and GCS backend"
```

---

### Task 4: Terraform — firewall rule

**Files:**
- Modify: `terraform/main.tf`

**Step 1: Add firewall resource to `terraform/main.tf`**

```hcl
resource "google_compute_firewall" "allow_ssh" {
  name    = "devbox-allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["devbox"]
}
```

**Step 2: Plan to verify**

```bash
cd terraform
terraform plan -var-file=terraform.tfvars
```

Expected: `Plan: 1 to add, 0 to change, 0 to destroy.`

**Step 3: Apply**

```bash
terraform apply -var-file=terraform.tfvars
```

Type `yes` when prompted. Expected: `Apply complete! Resources: 1 added.`

**Step 4: Commit**

```bash
git add terraform/main.tf
git commit -m "feat: add SSH firewall rule"
```

---

### Task 5: Terraform — VM instance

**Files:**
- Modify: `terraform/main.tf`

**Step 1: Add VM resource to `terraform/main.tf`**

```hcl
resource "google_compute_instance" "devbox" {
  name         = "zaeem-devbox"
  machine_type = "e2-standard-2"
  zone         = var.zone

  tags = ["devbox"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts"
      size  = 50
      type  = "pd-ssd"
    }
  }

  network_interface {
    network = "default"
    access_config {}  # ephemeral external IP
  }

  metadata = {
    ssh-keys = "zaeem:${var.ssh_public_key}"
  }

  # Allow stopping the instance without Terraform complaining
  allow_stopping_for_update = true
}
```

**Step 2: Plan to verify**

```bash
cd terraform
terraform plan -var-file=terraform.tfvars
```

Expected: `Plan: 1 to add, 0 to change, 0 to destroy.`

**Step 3: Apply**

```bash
terraform apply -var-file=terraform.tfvars
```

Expected: `Apply complete! Resources: 1 added.` Note the `external_ip` output.

**Step 4: Test SSH connectivity**

```bash
ssh -i ~/.ssh/zaeem_devbox zaeem@EXTERNAL_IP
```

Expected: Ubuntu login prompt. Type `exit` to disconnect.

**Step 5: Commit**

```bash
git add terraform/main.tf
git commit -m "feat: add GCP VM instance"
```

---

### Task 6: devbox environment — interview and devbox.json

**Files:**
- Create: `devbox/devbox.json`
- Create: `devbox/README.md`

**Step 1: Interview the user**

Before writing `devbox.json`, ask the user:
1. Which programming languages do you work with? (Python, Node/JS, Go, Ruby, Rust, etc.)
2. Do you need any databases locally? (Postgres, Redis, etc.)
3. Any CLI tools you use daily? (e.g., jq, ripgrep, fzf, awscli, etc.)
4. Do you use Docker on this machine?

**Step 2: Create `devbox/devbox.json` (baseline — expand based on interview)**

```json
{
  "$schema": "https://raw.githubusercontent.com/jetpack-io/devbox/0.10.1/.schema/devbox.schema.json",
  "packages": [
    "git@latest",
    "gh@latest",
    "zsh@latest",
    "tmux@latest",
    "nodejs@20",
    "python@3.12",
    "ripgrep@latest",
    "fzf@latest",
    "jq@latest",
    "curl@latest",
    "wget@latest",
    "unzip@latest"
  ],
  "shell": {
    "init_hook": [
      "echo 'devbox environment loaded'"
    ]
  }
}
```

> Add language-specific packages based on the interview. devbox package names follow nixpkgs — use `devbox search PACKAGE` to find exact names.

**Step 3: Validate locally**

```bash
cd devbox
devbox install
```

Expected: All packages install without error.

**Step 4: Create `devbox/README.md`**

```markdown
# Dev Environment

Managed by [devbox](https://www.jetpack.io/devbox/).

## Setup

Install devbox, then:

    cd devbox && devbox install

## Adding packages

    devbox add PACKAGE_NAME

Then commit the updated devbox.json.
```

**Step 5: Commit**

```bash
git add devbox/
git commit -m "feat: add devbox environment config"
```

---

### Task 7: Dotfiles — zsh config

**Files:**
- Create: `dotfiles/zshrc`

**Step 1: Create `dotfiles/zshrc`**

```zsh
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

# --- Prompt (minimal, no plugin manager needed) ---
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats ' (%b)'
setopt PROMPT_SUBST
PROMPT='%F{cyan}%~%f%F{yellow}${vcs_info_msg_0_}%f %# '

# --- Aliases ---
alias ll='ls -lah'
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline -20'
alias ..='cd ..'
alias ...='cd ../..'

# --- devbox ---
eval "$(devbox global shellenv)"

# --- fzf ---
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# --- Auto-attach tmux on SSH login ---
if [[ -n "$SSH_CONNECTION" ]] && [[ -z "$TMUX" ]]; then
  tmux new-session -A -s main
fi
```

> The last block auto-attaches to a tmux session named `main` on every SSH login — this is the key resilience feature.

**Step 2: Commit**

```bash
git add dotfiles/zshrc
git commit -m "feat: add zsh config with tmux auto-attach"
```

---

### Task 8: Dotfiles — tmux config

**Files:**
- Create: `dotfiles/tmux.conf`

**Step 1: Create `dotfiles/tmux.conf`**

```tmux
# --- Prefix key: Ctrl-a (easier than Ctrl-b) ---
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# --- Mouse support ---
set -g mouse on

# --- Window/pane numbering from 1 ---
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on

# --- Don't rename windows automatically ---
set-option -g allow-rename off

# --- Faster escape (important for vim/neovim) ---
set -sg escape-time 10

# --- Pane splitting with | and - (intuitive) ---
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# --- Pane navigation with vim keys ---
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# --- Status bar ---
set -g status-style 'bg=#1a1b26 fg=#a9b1d6'
set -g status-left '#[fg=#7aa2f7,bold] #S '
set -g status-right '#[fg=#9ece6a] %H:%M #[fg=#e0af68] %d %b '
set -g status-left-length 20
set -g window-status-current-style 'fg=#7aa2f7,bold'

# --- Keep windows alive after process exits ---
set -g remain-on-exit off

# --- 256 color support ---
set -g default-terminal "screen-256color"
```

**Step 2: Commit**

```bash
git add dotfiles/tmux.conf
git commit -m "feat: add tmux config"
```

---

### Task 9: Dotfiles — gitconfig

**Files:**
- Create: `dotfiles/gitconfig`

**Step 1: Ask the user for their git identity**

Ask: "What name and email should git use on the dev box?"

**Step 2: Create `dotfiles/gitconfig`**

```ini
[user]
    name = YOUR_NAME
    email = YOUR_EMAIL

[core]
    editor = vim
    autocrlf = input
    pager = less -FX

[init]
    defaultBranch = main

[pull]
    rebase = true

[push]
    default = simple
    autoSetupRemote = true

[alias]
    st = status
    co = checkout
    br = branch
    lg = log --oneline --graph --decorate -20
    unstage = reset HEAD --

[color]
    ui = auto
```

**Step 3: Commit**

```bash
git add dotfiles/gitconfig
git commit -m "feat: add gitconfig"
```

---

### Task 10: Dotfiles — bootstrap.sh

**Files:**
- Create: `dotfiles/bootstrap.sh`

This script runs once on the VM after first SSH login to wire everything up.

**Step 1: Create `dotfiles/bootstrap.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="$HOME"

echo "==> Bootstrapping dev box from $DOTFILES_DIR"

# --- Install devbox ---
if ! command -v devbox &>/dev/null; then
  echo "==> Installing devbox..."
  curl -fsSL https://get.jetpack.io/devbox | bash
fi

# --- Install devbox packages ---
echo "==> Installing devbox packages..."
devbox global add $(jq -r '.packages[]' "$DOTFILES_DIR/../devbox/devbox.json" | tr '\n' ' ')

# --- Symlink dotfiles ---
echo "==> Symlinking dotfiles..."
ln -sf "$DOTFILES_DIR/zshrc"     "$HOME_DIR/.zshrc"
ln -sf "$DOTFILES_DIR/tmux.conf" "$HOME_DIR/.tmux.conf"
ln -sf "$DOTFILES_DIR/gitconfig" "$HOME_DIR/.gitconfig"

# --- Set zsh as default shell ---
ZSH_PATH=$(which zsh)
if [ "$SHELL" != "$ZSH_PATH" ]; then
  echo "==> Setting zsh as default shell..."
  echo "$ZSH_PATH" | sudo tee -a /etc/shells
  chsh -s "$ZSH_PATH"
fi

# --- Install Claude Code ---
echo "==> Installing Claude Code..."
npm install -g @anthropic-ai/claude-code

echo ""
echo "Bootstrap complete! Log out and back in for shell change to take effect."
echo "Then run: tmux new-session -s main"
```

**Step 2: Make it executable**

```bash
chmod +x dotfiles/bootstrap.sh
```

**Step 3: Commit**

```bash
git add dotfiles/bootstrap.sh
git commit -m "feat: add bootstrap script"
```

---

### Task 11: Auto-stop systemd timer

**Files:**
- Create: `dotfiles/idle-check.sh`
- Create: `dotfiles/devbox-idle.service`
- Create: `dotfiles/devbox-idle.timer`
- Modify: `dotfiles/bootstrap.sh`

**Step 1: Create `dotfiles/idle-check.sh`**

```bash
#!/usr/bin/env bash
# Powers off the VM if CPU and Claude Code have been idle for 30 minutes.
# Intended to run every 10 minutes via systemd timer.

set -euo pipefail

IDLE_THRESHOLD_MINUTES=30
STATE_FILE="/tmp/last_active_time"
LOG="/var/log/idle-check.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# Check if Claude Code is running
if pgrep -f "claude" &>/dev/null; then
  log "Claude Code active — resetting idle timer"
  date +%s > "$STATE_FILE"
  exit 0
fi

# Check CPU usage (1-minute load average vs CPU count)
CPU_COUNT=$(nproc)
LOAD=$(awk '{print $1}' /proc/loadavg)
CPU_BUSY=$(awk -v load="$LOAD" -v cpus="$CPU_COUNT" 'BEGIN { print (load / cpus > 0.05) ? 1 : 0 }')

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
  sudo poweroff
fi
```

**Step 2: Create `dotfiles/devbox-idle.service`**

```ini
[Unit]
Description=Idle shutdown check for dev box

[Service]
Type=oneshot
ExecStart=/usr/local/bin/idle-check.sh
```

**Step 3: Create `dotfiles/devbox-idle.timer`**

```ini
[Unit]
Description=Run idle check every 10 minutes

[Timer]
OnBootSec=10min
OnUnitActiveSec=10min

[Install]
WantedBy=timers.target
```

**Step 4: Add systemd setup to `dotfiles/bootstrap.sh`**

Add these lines before the final `echo` in bootstrap.sh:

```bash
# --- Install idle-stop timer ---
echo "==> Installing idle-stop systemd timer..."
sudo cp "$DOTFILES_DIR/idle-check.sh" /usr/local/bin/idle-check.sh
sudo chmod +x /usr/local/bin/idle-check.sh
sudo cp "$DOTFILES_DIR/devbox-idle.service" /etc/systemd/system/devbox-idle.service
sudo cp "$DOTFILES_DIR/devbox-idle.timer"   /etc/systemd/system/devbox-idle.timer
sudo systemctl daemon-reload
sudo systemctl enable --now devbox-idle.timer
echo "==> Idle timer enabled (30min threshold, checks every 10min)"
```

**Step 5: Commit**

```bash
git add dotfiles/idle-check.sh dotfiles/devbox-idle.service dotfiles/devbox-idle.timer dotfiles/bootstrap.sh
git commit -m "feat: add auto-stop idle detection timer"
```

---

### Task 12: scripts/start.sh and scripts/stop.sh

**Files:**
- Create: `scripts/start.sh`
- Create: `scripts/stop.sh`

**Step 1: Create `scripts/start.sh`**

```bash
#!/usr/bin/env bash
# Start the dev box and SSH into it.
set -euo pipefail

INSTANCE="zaeem-devbox"
ZONE="us-central1-a"
PROJECT="YOUR_PROJECT_ID"
SSH_KEY="$HOME/.ssh/zaeem_devbox"
SSH_USER="zaeem"
SSH_CONFIG="$HOME/.ssh/config"

echo "==> Starting $INSTANCE..."
gcloud compute instances start "$INSTANCE" --zone="$ZONE" --project="$PROJECT"

echo "==> Waiting for SSH to be ready..."
for i in $(seq 1 30); do
  IP=$(gcloud compute instances describe "$INSTANCE" \
    --zone="$ZONE" --project="$PROJECT" \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
  if ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
       -i "$SSH_KEY" "${SSH_USER}@${IP}" true 2>/dev/null; then
    break
  fi
  echo "  attempt $i/30..."
  sleep 3
done

echo "==> VM is up at $IP"

# Patch ~/.ssh/config
if grep -q "Host devbox" "$SSH_CONFIG" 2>/dev/null; then
  sed -i.bak "s/HostName .*/HostName $IP/" "$SSH_CONFIG"
else
  cat >> "$SSH_CONFIG" <<EOF

Host devbox
  HostName $IP
  User $SSH_USER
  IdentityFile $SSH_KEY
  StrictHostKeyChecking no
EOF
fi

echo "==> Connecting (ssh devbox will work after this)..."
ssh devbox
```

**Step 2: Create `scripts/stop.sh`**

```bash
#!/usr/bin/env bash
# Manually stop the dev box.
set -euo pipefail

INSTANCE="zaeem-devbox"
ZONE="us-central1-a"
PROJECT="YOUR_PROJECT_ID"

echo "==> Stopping $INSTANCE..."
gcloud compute instances stop "$INSTANCE" --zone="$ZONE" --project="$PROJECT"
echo "==> Done."
```

**Step 3: Make executable**

```bash
chmod +x scripts/start.sh scripts/stop.sh
```

**Step 4: Commit**

```bash
git add scripts/
git commit -m "feat: add start/stop scripts"
```

---

### Task 13: GCP billing budget alerts

This is done in the GCP Console UI — no code required.

**Step 1: Open Billing in GCP Console**

Go to: Console → Billing → Budgets & alerts → Create budget

**Step 2: Configure the budget**

- Scope: your GCP project
- Budget type: Specified amount
- Amount: $50/month
- Alert thresholds:
  - 60% ($30) → email notification
  - 100% ($50) → email notification
- Actions: check "Email alerts to billing admins and users"

> Note: GCP does NOT auto-stop VMs when budget is hit by default. To hard-cap: enable the "Disable billing" action, but be aware this will stop ALL GCP services in the project, not just the VM. For a dedicated project this is acceptable.

**Step 3: Commit a record**

```bash
git commit --allow-empty -m "chore: GCP billing budget configured ($30 alert, $50 cap)"
```

---

### Task 14: First-boot end-to-end test

**Step 1: Start the VM**

```bash
./scripts/start.sh
```

Expected: VM starts, SSH connects, drops you into a bash shell.

**Step 2: Clone this repo on the VM**

```bash
git clone https://github.com/zaeemadamjee/zaeem_devbox.git ~/zaeem_devbox
```

**Step 3: Run bootstrap**

```bash
cd ~/zaeem_devbox && bash dotfiles/bootstrap.sh
```

Expected: devbox installs, dotfiles symlinked, zsh set as default shell, Claude Code installed, idle timer enabled.

**Step 4: Log out and back in**

```bash
exit
ssh devbox
```

Expected: You land inside a tmux session automatically (window named `main`).

**Step 5: Verify tools**

```bash
tmux -V          # tmux 3.x
zsh --version    # zsh 5.x
claude --version # Claude Code
git --version
```

**Step 6: Test idle timer**

```bash
sudo systemctl status devbox-idle.timer
```

Expected: `active (waiting)` with next trigger time shown.

**Step 7: Disconnect and verify auto-stop**

Leave the VM idle (no activity, no Claude Code running). After 30 minutes it should shut itself down. Verify in GCP Console that the instance status changes to `TERMINATED`.

---

## Summary of files created

```
terraform/
  main.tf
  variables.tf
  outputs.tf
  .gitignore
  terraform.tfvars.example

devbox/
  devbox.json
  README.md

dotfiles/
  zshrc
  tmux.conf
  gitconfig
  bootstrap.sh
  idle-check.sh
  devbox-idle.service
  devbox-idle.timer

scripts/
  start.sh
  stop.sh
```
