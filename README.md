# zaeem_devbox

A fully reproducible GCP cloud dev box, provisioned from scratch with Terraform and configured via devbox + dotfiles. The goal is a single SSH command away from a complete dev environment — on any machine, after any reprovisioning. Nothing requires manual one-off steps: all infrastructure is declared in Terraform, all tools are pinned in `devbox/devbox.json`, and all shell config is committed in `dotfiles/`.

**Workflow:** create a profile, run Terraform to create the VM, SSH in, and the bootstrap script wires everything up automatically on first login.

---

## Profiles

All per-VM configuration lives in `scripts/profiles/<name>.sh`. Every operational script requires `--profile <name>`.

A profile declares:

- GCP project, region, zone, instance name
- VM machine type and disk size
- SSH public keys (one per local machine that needs access)
- Repos to clone into `~/workspace` on first login
- GCP Secret Manager secrets to fetch on bootstrap
- Whether to install the idle shutdown timer

To add a new VM, copy an existing profile and update it:

```bash
cp scripts/profiles/personal.sh scripts/profiles/myproject.sh
# edit scripts/profiles/myproject.sh
```

---

## Prerequisites Checklist

### 1. GCP Account & Project

- A **GCP account** with billing enabled
- A **GCP project** — set per profile in `GCP_PROJECT`

### 2. Local CLI Tools (on your Mac)

- `gcloud` CLI — authenticated (`gcloud auth login`)
- `terraform` >= 1.6 (`brew tap hashicorp/tap && brew install hashicorp/tap/terraform`)
- `git`, `ssh`, `curl`, `python3` — all standard on macOS

### 3. SSH Key

- An ed25519 SSH key at `~/.ssh/zaeem_devbox` — `**scripts/setup-gcp-prereqs.sh` generates this for you**
- Add the public key content (`cat ~/.ssh/zaeem_devbox.pub`) to the `SSH_PUBLIC_KEYS` array in your profile
- Repeat for each machine that needs access to the VM

### 4. GCS State Bucket

- One bucket per GCP project, named `<project-id>-zaeem-devbox-tf-state`
- Created automatically by `initialize.sh` — no manual step needed
- State is stored per profile at `gs://<project-id>-zaeem-devbox-tf-state/<profile-name>/`

### 5. GitHub SSH Access

- Your GitHub account must have an SSH key so the VM can clone `git@github.com:zaeemadamjee/zaeem_devbox.git` on first boot
- Your local SSH agent must be running with your GitHub key loaded (agent forwarding is enabled in `start.sh`)

### 6. Update `dotfiles/gitconfig`

- Hardcoded name/email — update with your actual identity before provisioning

### 7. GCP Secrets

- Any secrets listed in a profile's `SECRETS` array must exist in GCP Secret Manager in the profile's project
- The secret name in Secret Manager must match the env var name exactly (e.g. `ANTHROPIC_API_KEY`)

### 8. GCP Billing Alerts (optional but recommended)

- Manual setup in GCP Console — the repo uses `$30 alert / $50 hard cap` — see `docs/billing-setup.md`

---

## Provisioning a New VM

### First-time provision

```bash
# 1. Authenticate and set the target project
gcloud auth login
gcloud config set project <project-id>

# 2. Create a profile
cp scripts/profiles/personal.sh scripts/profiles/<name>.sh
# edit scripts/profiles/<name>.sh — set GCP_PROJECT, instance name, repos, etc.

# 3. Run initialize — handles APIs, SSH key, state bucket, and terraform apply in one go
scripts/initialize.sh --profile <name>
# (if your SSH key isn't in the profile yet, the script will print it and pause)

# 4. Start and SSH in (bootstrap runs automatically on first login)
scripts/start.sh --profile <name>
```

> **Note:** `initialize.sh` is for first-time provisioning only. For subsequent wipe-and-recreate, use `reset.sh` instead.

### Reprovisioning (wipe and recreate an existing VM)

```bash
# Destroys and recreates the VM — all disk data is lost
scripts/reset.sh --profile <name>
scripts/start.sh --profile <name>
```

---

## Daily Usage

```bash
# Start VM and SSH in
scripts/start.sh --profile personal

# Stop VM immediately (disk persists, no compute charges)
scripts/stop.sh --profile personal

# Wipe and recreate VM with a fresh disk
scripts/reset.sh --profile personal
```

The SSH config entry is named `devbox-<profile>` (e.g. `devbox-personal`), so you can also SSH directly:

```bash
ssh devbox-personal
```

---

## Connecting from Multiple Machines

Add each machine's public key to `SSH_PUBLIC_KEYS` in the profile, then run `scripts/reset.sh --profile <name>` to apply. All keys are written to the VM's `authorized_keys` via Terraform.

Each local machine runs `scripts/start.sh --profile <name>` independently — it updates that machine's `~/.ssh/config` entry with the current ephemeral IP.

---

## Aliases (optional)

```bash
echo 'alias devbox="~/Documents/git/zaeem_devbox/scripts/start.sh --profile personal"' >> ~/.zshrc
echo 'alias devbox-stop="~/Documents/git/zaeem_devbox/scripts/stop.sh --profile personal"' >> ~/.zshrc
source ~/.zshrc
```

