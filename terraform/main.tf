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
  # This is handled automatically by scripts/reset.sh and scripts/start.sh
  # via terraform_init_profile in scripts/lib/profile.sh.
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

resource "google_service_account" "otelcol" {
  account_id   = "otelcol-exporter"
  display_name = "OTel Collector Exporter"
}

resource "google_project_iam_member" "otelcol_metrics" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.otelcol.email}"
}

resource "google_project_iam_member" "otelcol_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.otelcol.email}"
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
    access_config {}  # ephemeral external IP
  }

  service_account {
    email  = google_service_account.otelcol.email
    scopes = ["cloud-platform"]
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

      echo "[startup] Installing system packages..."
      apt-get update -y
      apt-get install -y git curl zsh

      echo "[startup] Installing gum (charm.sh)..."
      mkdir -p /etc/apt/keyrings
      curl -fsSL https://repo.charm.sh/apt/gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null
      echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
        > /etc/apt/sources.list.d/charm.list
      apt-get update -qq && apt-get install -y -qq gum

      echo "[startup] Ensuring zaeem user exists..."
      if ! id zaeem &>/dev/null; then
        useradd -m -s /bin/bash zaeem
      fi
      echo "zaeem ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/zaeem
      chmod 440 /etc/sudoers.d/zaeem

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
# Pre-bootstrap stub — replaced by bootstrap.sh with the real dotfiles/zshrc symlink.
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
  [[ -f "$REPO/dotfiles/welcome.sh" ]] && source "$REPO/dotfiles/welcome.sh"
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
