#!/usr/bin/env bash
# profiles/mini.sh — Profile for the mini devbox VM.

PROFILE_NAME="mini"

# --- GCP settings ---
GCP_PROJECT="zaeem-dev"
GCP_REGION="us-central1"
GCP_INSTANCE_NAME="zaeem-devbox-mini"

# --- VM hardware ---
VM_MACHINE_TYPE="e2-micro"
VM_DISK_SIZE=10

# --- Features ---
IDLE_TIMER_ENABLED=false

# --- SSH public keys ---
# Add one entry per machine that needs SSH access to this VM.
# Get the value with: cat ~/.ssh/zaeem_devbox.pub
SSH_PUBLIC_KEYS=(
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIgTtXgAtaDgH+tPrmktwEt2T1bkHPx4/5PY8Eb1HoHk zaeem-devbox"
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN1v/HZNzmUlFfOukhbujYHHoaWfs5hJz3qK+x+1bNqr termius"
  # "ssh-ed25519 AAAA... zaeem@machine2"
)

# --- Repos to clone into ~/workspace on first login ---
REPOS=(
  "git@github.com:zaeemadamjee/travel_agent.git"
)
