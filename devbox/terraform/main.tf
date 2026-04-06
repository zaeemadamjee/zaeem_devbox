terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Partial backend — bucket and prefix are supplied at init time:
  #   terraform init \
  #     -backend-config="bucket=zaeem-devbox-tf-state" \
  #     -backend-config="prefix=<profile-name>"
  #
  # This is handled automatically by bin/reset and bin/start
  # via terraform_init_profile in devbox/lib/profile.
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_compute_zones" "available" {
  region = var.region
}

locals {
  zone = var.zone != "" ? var.zone : data.google_compute_zones.available.names[0]
}


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

resource "google_compute_firewall" "allow_ports" {
  # Only created when the profile specifies extra ports to open.
  count   = length(var.firewall_allow_ports) > 0 ? 1 : 0
  name    = "${var.instance_name}-allow-ports"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = var.firewall_allow_ports
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["devbox"]
}

resource "google_compute_address" "devbox" {
  count  = var.static_ip ? 1 : 0
  name   = "${var.instance_name}-ip"
  region = var.region
}

resource "google_compute_instance" "devbox" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = local.zone

  tags = ["devbox"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = var.disk_size
      type  = "pd-ssd"
    }
  }

  network_interface {
    network = "default"
    access_config {
      # nat_ip = null → ephemeral IP; set to reserved address when static_ip = true
      nat_ip = var.static_ip ? google_compute_address.devbox[0].address : null
    }
  }

  metadata = {
    # SSH access — one "zaeem:<pubkey>" entry per machine
    ssh-keys = join("\n", [for key in var.ssh_public_keys : "zaeem:${key}"])

    # Profile metadata — read by bootstrap.sh and clone-repos.sh on the VM
    devbox-profile            = var.profile_name
    devbox-idle-timer-enabled = tostring(var.idle_timer_enabled)
    devbox-repos              = join("\n", var.repos)

    startup-script = <<-EOF
      #!/bin/bash
      set -euo pipefail
      exec > /var/log/startup-script.log 2>&1

      # Only run once — leave a marker file
      MARKER="/var/lib/startup-complete"
      [ -f "$MARKER" ] && exit 0

      # Create the zaeem user and inject SSH keys immediately — before apt or
      # anything else — so that sshd can authenticate as soon as it is up.
      # The google-guest-agent injects keys on a ~30s sync cycle which may
      # race with the SSH readiness poll; writing authorized_keys directly
      # here removes that dependency entirely.
      echo "[startup] Creating zaeem user and installing SSH keys..."
      if ! id zaeem &>/dev/null; then
        useradd -m -s /bin/bash zaeem
      fi
      echo "zaeem ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/zaeem
      chmod 440 /etc/sudoers.d/zaeem

      mkdir -p /home/zaeem/.ssh
      chmod 700 /home/zaeem/.ssh
      # Pull authorized keys from instance metadata (format: "zaeem:<pubkey>\n...")
      curl -sf -H "Metadata-Flavor: Google" \
        "http://metadata.google.internal/computeMetadata/v1/instance/attributes/ssh-keys" \
        | sed 's/^zaeem://' > /home/zaeem/.ssh/authorized_keys || true
      chmod 600 /home/zaeem/.ssh/authorized_keys
      chown -R zaeem:zaeem /home/zaeem/.ssh

      # cloud-init and unattended-upgrades hold the dpkg lock during early boot.
      # Wait up to 5 minutes for the lock to clear before touching apt.
      echo "[startup] Waiting for apt lock..."
      timeout 300 bash -c '
        while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
          sleep 2
        done
      ' || { echo "[startup] ERROR: apt lock held for >5 min — aborting"; exit 1; }

      echo "[startup] Adding charm.sh apt repo..."
      mkdir -p /etc/apt/keyrings
      curl -fsSL https://repo.charm.sh/apt/gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
      echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
        > /etc/apt/sources.list.d/charm.list

      echo "[startup] Installing system packages..."
      apt-get update -y
      apt-get install -y git curl zsh gum

      echo "[startup] Suppressing Ubuntu MOTD..."
      touch /home/zaeem/.hushlogin
      chown zaeem:zaeem /home/zaeem/.hushlogin

      echo "[startup] Writing profile name to ~/.config/devbox/profile..."
      mkdir -p /home/zaeem/.config/devbox
      printf '%s\n' "${var.profile_name}" > /home/zaeem/.config/devbox/profile
      chown -R zaeem:zaeem /home/zaeem/.config

      echo "[startup] Configuring SSH for zaeem..."
      mkdir -p /home/zaeem/.ssh
      chmod 700 /home/zaeem/.ssh
      # StrictHostKeyChecking=accept-new: auto-trust new keys, reject changed keys (MITM protection).
      # This is deterministic — no network call needed, so no timing issues at early boot.
      cat > /home/zaeem/.ssh/config <<'SSH_CONFIG'
Host github.com
  StrictHostKeyChecking accept-new
SSH_CONFIG
      chmod 600 /home/zaeem/.ssh/config
      # Also try ssh-keyscan as belt-and-suspenders (may fail on early boot — non-fatal).
      ssh-keyscan -H github.com >> /home/zaeem/.ssh/known_hosts 2>/dev/null || true
      chown -R zaeem:zaeem /home/zaeem/.ssh

      echo "[startup] Writing pre-bootstrap ~/.zshrc stub..."
      cat > /home/zaeem/.zshrc <<'ZSHRC'
# Pre-bootstrap stub — replaced by devbox/bin/bootstrap (stow zsh) with the real config/zsh/.zshrc symlink.
if [[ ! -f "$HOME/.bootstrap-complete" ]]; then
  REPO="$HOME/zaeem_devbox"

  # Ensure GitHub host key is trusted on every login (idempotent).
  # StrictHostKeyChecking=accept-new: auto-accepts new keys, rejects changed ones.
  # Done here (not just in startup-script) so it applies even to pre-existing VMs.
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  if ! grep -q 'github.com' "$HOME/.ssh/config" 2>/dev/null; then
    printf 'Host github.com\n  StrictHostKeyChecking accept-new\n' >> "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
  fi

  if [[ ! -d "$REPO" ]]; then
    if [[ -z "$${SSH_AUTH_SOCK:-}" ]]; then
      echo ""
      echo "  ⚠  SSH agent required to clone zaeem_devbox."
      echo "     Load your key locally:  ssh-add ~/.ssh/zaeem_devbox"
      echo "     Then reconnect."
      echo ""
    else
      gum spin --spinner dot --title "  Cloning zaeem_devbox..." -- \
        timeout 60 git clone git@github.com:zaeemadamjee/zaeem_devbox.git "$REPO"
    fi
  fi
  [[ -f "$REPO/devbox/bin/welcome" ]] && source "$REPO/devbox/bin/welcome"
fi
ZSHRC
      chown zaeem:zaeem /home/zaeem/.zshrc

      echo "[startup] Setting zsh as default shell..."
      ZSH_PATH=$(command -v zsh)
      usermod -s "$ZSH_PATH" zaeem

      touch "$MARKER"
      echo "[startup] Done — VM ready."
    EOF
  }

  # Allow stopping the instance without Terraform complaining
  allow_stopping_for_update = true
}
