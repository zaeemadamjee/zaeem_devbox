# zaeem_devbox

A fully reproducible GCP cloud dev box, provisioned from scratch with Terraform and configured via devbox + dotfiles. The goal is a single SSH command away from a complete dev environment — on any machine, after any reprovisioning. Nothing requires manual one-off steps: all infrastructure is declared in Terraform, all tools are pinned in `devbox/devbox.json`, and all shell config is committed in `dotfiles/`.

**Workflow:** run Terraform to create the VM, SSH in, and the bootstrap script wires everything up automatically on first login.

---

## Prerequisites Checklist

### 1. GCP Account & Project
- A **GCP account** with billing enabled
- A **GCP project** — the repo defaults to `zaeem-dev` as the project ID. If you use a different name, update it in:
  - `scripts/start.sh`, `scripts/stop.sh`, `scripts/setup-gcp-prereqs.sh`, `scripts/setup-gcs-state.sh`
  - `dotfiles/otelcol-contrib-config.yaml`

### 2. Local CLI Tools (on your Mac)
- `gcloud` CLI — authenticated (`gcloud auth login` + `gcloud config set project zaeem-dev`)
- `terraform` >= 1.6 (`brew tap hashicorp/tap &&
brew install hashicorp/tap/terraform`)
- `git`, `ssh`, `curl`, `python3` — all standard on macOS

### 3. SSH Key
- An ed25519 SSH key at `~/.ssh/zaeem_devbox` — **`scripts/setup-gcp-prereqs.sh` generates this for you**
- The **public key content** (`~/.ssh/zaeem_devbox.pub`) goes into `terraform/terraform.tfvars`

### 4. `terraform/terraform.tfvars` (gitignored, must create manually)
Copy from `terraform.tfvars.example` and fill in:
```hcl
project_id     = "zaeem-dev"
ssh_public_key = "ssh-ed25519 AAAA..."   # from setup-gcp-prereqs.sh output
```

### 5. GCS State Bucket
- Must be created **before** `terraform init` — run `scripts/setup-gcs-state.sh`
- Bucket name `zaeem-tf-state` is globally unique in GCP; if taken, update it in both that script and `terraform/main.tf`

### 6. GitHub SSH Access
- Your GitHub account must have an SSH key so the VM can clone `git@github.com:zaeemadamjee/zaeem_devbox.git` on first boot
- Your local SSH agent must be running with your GitHub key loaded (agent forwarding is enabled in `start.sh`)

### 7. Update `dotfiles/gitconfig`
- Hardcoded name/email — update with your actual identity before provisioning

### 8. Anthropic Account (post-provision)
- Claude Code (`claude`) is auto-installed by bootstrap — you'll be prompted to authenticate on first run

### 9. GCP Billing Alerts (optional but recommended)
- Manual setup in GCP Console — the repo uses `$30 alert / $50 hard cap` — see `docs/billing-setup.md`

---

## Provisioning Order

```
1. gcloud auth login && gcloud config set project zaeem-dev
2. scripts/setup-gcp-prereqs.sh     # enables APIs, generates SSH key
3. scripts/setup-gcs-state.sh       # creates Terraform state bucket
4. cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   # fill in project_id + ssh_public_key
5. cd terraform && terraform init && terraform apply
6. scripts/start.sh                 # starts VM, SSH in, bootstrap runs automatically
```
