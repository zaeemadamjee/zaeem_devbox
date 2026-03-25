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
SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=30 -i "$SSH_KEY")

# ---------------------------------------------------------------------------
# Early agent check — warn now so the user can fix before connecting
# ---------------------------------------------------------------------------
if ! ssh-add -l &>/dev/null; then
  echo ""
  echo "  Warning: SSH agent has no keys loaded."
  echo "  If this is a fresh VM, the repo clone will fail without agent forwarding."
  echo "  Fix: ssh-add ~/.ssh/zaeem_devbox"
  echo ""
fi

echo "==> Starting $GCP_INSTANCE_NAME (profile: $PROFILE_NAME)..."
gcloud compute instances start "$GCP_INSTANCE_NAME" \
  --zone="$GCP_ZONE" --project="$GCP_PROJECT" --quiet

echo "==> Waiting for SSH to be ready..."
IP=""
SSH_READY="false"
for i in $(seq 1 30); do
  IP=$(gcloud compute instances describe "$GCP_INSTANCE_NAME" \
    --zone="$GCP_ZONE" --project="$GCP_PROJECT" \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || true)
  if [ -n "$IP" ] && ssh "${SSH_OPTS[@]}" -o BatchMode=yes \
       "${SSH_USER}@${IP}" true 2>/dev/null; then
    SSH_READY="true"
    break
  fi
  echo "  attempt $i/30..."
  sleep 5
done

if [ -z "$IP" ] || [ "$SSH_READY" != "true" ]; then
  echo "ERROR: Could not reach VM over SSH after 30 attempts" >&2
  exit 1
fi

echo "==> VM is up at $IP"

# Wait for the GCP startup script to fully complete before connecting.
# It leaves a marker at /var/lib/startup-complete when done.
echo "==> Waiting for startup script to complete..."
for i in $(seq 1 20); do
  if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "${SSH_USER}@${IP}" \
       "sudo test -f /var/lib/startup-complete" 2>/dev/null; then
    echo "    Startup complete."
    break
  fi
  echo "  still initializing... ($i/20)"
  sleep 5
done

# Remove stale known_hosts entry — VM gets new host keys after each reset
ssh-keygen -R "$IP" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Copy profile secrets file to VM if present (gitignored: scripts/profiles/<name>.env)
# ---------------------------------------------------------------------------
LOCAL_SECRETS="$SCRIPTS_DIR/profiles/${PROFILE_NAME}.env"
if [[ -f "$LOCAL_SECRETS" ]]; then
  echo "==> Copying secrets (${PROFILE_NAME}.env) to ~/.config/secrets.env..."
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${IP}" "mkdir -p ~/.config && chmod 700 ~/.config"
  scp -o StrictHostKeyChecking=no -i "$SSH_KEY" \
    "$LOCAL_SECRETS" "${SSH_USER}@${IP}:.config/secrets.env"
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${IP}" "chmod 600 ~/.config/secrets.env"
  echo "    Done."
else
  echo "==> No secrets file at ${LOCAL_SECRETS} — skipping"
fi

# ---------------------------------------------------------------------------
# Install Ghostty terminfo on the VM so the terminal renders correctly
# ---------------------------------------------------------------------------
echo "==> Copying Ghostty terminfo to devbox..."
if infocmp -x | ssh "${SSH_OPTS[@]}" "${SSH_USER}@${IP}" -- tic -x - 2>/dev/null; then
  echo "    Ghostty terminfo installed."
else
  echo "    Warning: could not install Ghostty terminfo (non-fatal, will retry on next start)."
fi

# ---------------------------------------------------------------------------
# Patch or create ~/.ssh/config entry for this profile's VM
# ---------------------------------------------------------------------------
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

if grep -q "^Host ${SSH_HOST}$" "$SSH_CONFIG" 2>/dev/null; then
  # Update existing entry's HostName
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
  echo "==> Updated SSH config: $SSH_HOST -> $IP"
else
  # Add new entry
  cat >> "$SSH_CONFIG" <<EOF

Host ${SSH_HOST}
  HostName $IP
  User $SSH_USER
  IdentityFile $SSH_KEY
  StrictHostKeyChecking no
  ForwardAgent yes
  ConnectTimeout 30
EOF
  echo "==> Added $SSH_HOST to SSH config"
fi

echo "==> Connecting to $SSH_HOST..."
ssh "$SSH_HOST"
