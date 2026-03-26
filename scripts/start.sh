#!/usr/bin/env bash
# start.sh — Start a devbox VM and SSH into it.
#
# Usage: ./scripts/start.sh --profile <name>
#
# Adds a "devbox-<profile>" entry to ~/.ssh/config on first run.
# Updates HostName with the current ephemeral IP on subsequent runs.

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/lib/profile.sh"

PROFILE=$(parse_profile_flag "$@")
load_profile "$PROFILE"
check_gcp_project
resolve_instance_zone

SSH_KEY="$HOME/.ssh/zaeem_devbox"
SSH_USER="zaeem"
SSH_CONFIG="$HOME/.ssh/config"
SSH_HOST="devbox-${PROFILE_NAME}"

# ---------------------------------------------------------------------------
# SSH agent check
# ---------------------------------------------------------------------------
if ! ssh-add -l &>/dev/null; then
  echo
  gum style --border rounded --padding "0 2" --border-foreground 214 \
    "$(gum style --foreground 214 --bold "⚠  SSH agent has no keys loaded")" \
    "" \
    "$(gum style --foreground 240 "If this is a fresh VM, the repo clone will fail without agent forwarding.")" \
    "$(gum style --foreground 240 "Fix: ssh-add ~/.ssh/zaeem_devbox")"
  echo
fi

# ---------------------------------------------------------------------------
# VM: start + wait for SSH + wait for startup script
# ---------------------------------------------------------------------------
section "VM ($GCP_INSTANCE_NAME)"

gum spin --spinner dot --title " Starting $GCP_INSTANCE_NAME..." -- \
  gcloud compute instances start "$GCP_INSTANCE_NAME" \
    --zone="$GCP_ZONE" --project="$GCP_PROJECT" --quiet
ok "Instance started"

# Poll for SSH readiness — runs inside gum spin via exported function so the
# spinner stays visible during the retry loop.
_poll_ssh() {
  local instance="$1" zone="$2" project="$3" user="$4" key="$5" out="$6"
  for i in $(seq 1 30); do
    local ip
    ip=$(gcloud compute instances describe "$instance" \
      --zone="$zone" --project="$project" \
      --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || true)
    if [[ -n "$ip" ]] && ssh \
         -o StrictHostKeyChecking=no -o ConnectTimeout=30 \
         -i "$key" -o BatchMode=yes "${user}@${ip}" true 2>/dev/null; then
      echo "$ip" > "$out"
      return 0
    fi
    sleep 5
  done
  return 1
}
export -f _poll_ssh

IP_FILE=$(mktemp)
trap 'rm -f "$IP_FILE"' EXIT

if ! gum spin --spinner dot --title " Waiting for SSH (up to 2.5 min)..." -- \
     bash -c "_poll_ssh '$GCP_INSTANCE_NAME' '$GCP_ZONE' '$GCP_PROJECT' '$SSH_USER' '$SSH_KEY' '$IP_FILE'"; then
  fail "Could not reach VM over SSH after 30 attempts"
  exit 1
fi
IP=$(cat "$IP_FILE")
ok "VM is up at $IP"

# Poll for startup script completion
_poll_startup() {
  local user="$1" ip="$2" key="$3"
  for i in $(seq 1 30); do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 \
         -i "$key" -o BatchMode=yes "${user}@${ip}" \
         "sudo test -f /var/lib/startup-complete" 2>/dev/null; then
      return 0
    fi
    sleep 5
  done
  return 1
}
export -f _poll_startup

if ! gum spin --spinner dot --title " Waiting for startup script to complete (up to 2.5 min)..." -- \
     bash -c "_poll_startup '$SSH_USER' '$IP' '$SSH_KEY'"; then
  warn "Startup script did not complete within expected time — connecting anyway"
else
  ok "Startup script complete"
fi

ssh-keygen -R "$IP" &>/dev/null || true

# ---------------------------------------------------------------------------
# Setup: secrets, terminfo
# ---------------------------------------------------------------------------
section "Setup"

LOCAL_SECRETS="$SCRIPTS_DIR/profiles/${PROFILE_NAME}.env"
if [[ -f "$LOCAL_SECRETS" ]]; then
  if gum spin --spinner dot --title " Copying secrets (${PROFILE_NAME}.env)..." -- bash -c "
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 -i '$SSH_KEY' \
      '${SSH_USER}@${IP}' 'mkdir -p ~/.config && chmod 700 ~/.config'
    scp -o StrictHostKeyChecking=no -i '$SSH_KEY' \
      '$LOCAL_SECRETS' '${SSH_USER}@${IP}:.config/secrets.env'
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 -i '$SSH_KEY' \
      '${SSH_USER}@${IP}' 'chmod 600 ~/.config/secrets.env'
  "; then
    ok "Secrets copied to ~/.config/secrets.env"
  else
    warn "Failed to copy secrets — you can retry by re-running start.sh"
  fi
else
  warn "No secrets file at ${LOCAL_SECRETS} — skipping"
fi

if gum spin --spinner dot --title " Installing Ghostty terminfo..." -- bash -c "
  infocmp -x | ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 \
    -i '$SSH_KEY' '${SSH_USER}@${IP}' -- tic -x - 2>/dev/null
"; then
  ok "Ghostty terminfo installed"
else
  warn "Could not install Ghostty terminfo (non-fatal, will retry on next start)"
fi

# ---------------------------------------------------------------------------
# SSH config: add or update devbox-<profile> entry
# ---------------------------------------------------------------------------
section "SSH config"

touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

if grep -q "^Host ${SSH_HOST}$" "$SSH_CONFIG" 2>/dev/null; then
  python3 - "$SSH_CONFIG" "$IP" "$SSH_HOST" <<'PYEOF'
import sys, re
config_file, new_ip, host = sys.argv[1], sys.argv[2], sys.argv[3]
with open(config_file) as f:
    content = f.read()
content = re.sub(
    r'(Host ' + re.escape(host) + r'\n(?:[ \t]+\S.*\n)*?[ \t]+HostName )\S+',
    lambda m: m.group(1) + new_ip,
    content
)
with open(config_file, 'w') as f:
    f.write(content)
PYEOF
  ok "Updated $SSH_HOST → $IP"
else
  cat >> "$SSH_CONFIG" <<EOF

Host ${SSH_HOST}
  HostName $IP
  User $SSH_USER
  IdentityFile $SSH_KEY
  StrictHostKeyChecking no
  ForwardAgent yes
  ConnectTimeout 30
EOF
  ok "Added $SSH_HOST to SSH config"
fi

echo
gum style --bold --foreground 99 "  Connecting to $SSH_HOST..."
echo
ssh -A "$SSH_HOST"
