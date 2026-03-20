#!/usr/bin/env bash
# profiles/personal.sh — Profile for the personal devbox VM.

PROFILE_NAME="personal"

# --- GCP settings ---
GCP_PROJECT="zaeem-dev"
GCP_REGION="us-east4"
GCP_INSTANCE_NAME="zaeem-devbox"

# --- VM hardware ---
VM_MACHINE_TYPE="e2-standard-2"
VM_DISK_SIZE=50

# --- Features ---
IDLE_TIMER_ENABLED=true

# --- SSH public keys ---
# Add one entry per machine that needs SSH access to this VM.
# Get the value with: cat ~/.ssh/zaeem_devbox.pub
SSH_PUBLIC_KEYS=(
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIgTtXgAtaDgH+tPrmktwEt2T1bkHPx4/5PY8Eb1HoHk zaeem-devbox"
  # "ssh-ed25519 AAAA... zaeem@machine2"
)

# --- Repos to clone into ~/workspace on first login ---
REPOS=(
  "git@github.com:zaeemadamjee/travel_agent.git"
)

# --- GCP Secret Manager secrets to fetch ---
# Each value is a secret name in Secret Manager (also used as the env var name).
SECRETS=(
  "ANTHROPIC_API_KEY"
)
