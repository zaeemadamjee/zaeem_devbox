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

resource "google_project_iam_member" "devbox_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
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
    devbox-secrets            = join("\n", var.secrets)

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

      echo "[startup] Ensuring zaeem user exists..."
      if ! id zaeem &>/dev/null; then
        useradd -m -s /bin/bash zaeem
      fi
      echo "zaeem ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/zaeem
      chmod 440 /etc/sudoers.d/zaeem

      echo "[startup] Writing first-login bootstrap trigger..."
      cat > /home/zaeem/.zshrc <<'ZSHRC'
# Temporary .zshrc — clones zaeem_devbox and bootstraps on first SSH login.
# Replaced by bootstrap.sh with the real dotfiles/zshrc symlink.
if [[ ! -f "$HOME/.bootstrap-complete" ]] && [[ -n "$${SSH_AUTH_SOCK:-}" ]]; then
  echo "==> First login: cloning zaeem_devbox..."
  git clone git@github.com:zaeemadamjee/zaeem_devbox.git "$HOME/zaeem_devbox"
  echo "==> Running bootstrap..."
  bash "$HOME/zaeem_devbox/dotfiles/bootstrap.sh" && touch "$HOME/.bootstrap-complete"
  echo "==> Reloading shell with full config..."
  exec zsh
fi
ZSHRC
      chown zaeem:zaeem /home/zaeem/.zshrc

      echo "[startup] Setting zsh as default shell..."
      ZSH_PATH=$(command -v zsh)
      usermod -s "$ZSH_PATH" zaeem

      touch "$MARKER"
      echo "[startup] Done — VM ready. Full bootstrap runs on first SSH login."
    EOF
  }

  # Allow stopping the instance without Terraform complaining
  allow_stopping_for_update = true
}
