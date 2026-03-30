# zaeem_devbox

A fully reproducible GCP cloud dev box, provisioned from scratch with Terraform and configured via devbox + dotfiles. The goal is a single SSH command away from a complete dev environment — on any machine, after any reprovisioning. Nothing requires manual one-off steps: all infrastructure is declared in Terraform, all tools are pinned in `devbox/devbox.json`, and all shell config is committed in `dotfiles/`.

**Workflow:** create a profile, then run `orchestrator.sh` — an interactive TUI menu that shows live VM status across all profiles and lets you pick start / stop / reset / initialize. The welcome screen walks you through bootstrap on first login.

---

## How it works

```
Terraform startup-script (runs once on provision)
  → installs git, curl, zsh, gum
  → creates zaeem user, sets zsh as default shell
  → writes profile name to ~/.config/devbox/profile
  → writes pre-bootstrap ~/.zshrc stub

orchestrator.sh (run locally — interactive TUI)
  → shows GCP auth status + live VM state for all profiles
  → profile + action selection menu (start / stop / reset / initialize)
  → delegates to the appropriate subscript

start.sh (called by orchestrator or directly)
  → starts VM, waits for SSH + startup-script to finish
  → copies scripts/profiles/<name>.env secrets to ~/.config/secrets.env
  → installs Ghostty terminfo
  → updates ~/.ssh/config with current ephemeral IP
  → ssh devbox-<profile>

On first interactive login (via the stub ~/.zshrc)
  → clones zaeem_devbox repo (requires SSH agent forwarding)
  → welcome screen prompts to run bootstrap

bootstrap.sh (idempotent, re-runnable)
  → installs devbox + pulls global packages
  → symlinks all dotfiles
  → installs TPM, otelcol, idle timer, Claude Code, opencode
  → symlinks real ~/.zshrc — subsequent logins skip the welcome screen
```

---

## Profiles

All per-VM configuration lives in `scripts/profiles/<name>.sh`. Every operational script requires `--profile <name>`.

A profile declares:

- GCP project, region, zone, instance name
- VM machine type and disk size
- SSH public keys (one per local machine that needs access)
- Repos to clone into `~/workspace` on first login
- Whether to install the idle shutdown timer

To add a new VM, copy an existing profile and update it:

```bash
cp scripts/profiles/personal.sh scripts/profiles/myproject.sh
# edit scripts/profiles/myproject.sh
```

Then run `scripts/orchestrator.sh` and select `initialize` to provision it.

---

## Secrets

Secrets are stored in a gitignored `.env` file alongside the profile and copied to the VM by `start.sh` before you connect:

```bash
# scripts/profiles/personal.env  (gitignored — never committed)
export ANTHROPIC_API_KEY=sk-ant-...
export SOME_OTHER_SECRET=...
```

`start.sh` copies this file to `~/.config/secrets.env` on the VM. The real `~/.zshrc` sources it on every login.

---

## Prerequisites Checklist

### 1. GCP Account & Project

- A **GCP account** with billing enabled
- A **GCP project** — set per profile in `GCP_PROJECT`

### 2. Local CLI Tools (on your Mac)

- `gum` — TUI toolkit used by all local scripts (`brew install gum`)
- `gcloud` CLI — authenticated (`gcloud auth login`)
- `terraform` >= 1.6 (`brew tap hashicorp/tap && brew install hashicorp/tap/terraform`)
- `git`, `ssh`, `curl`, `python3` — all standard on macOS

### 3. SSH Key

- An ed25519 SSH key at `~/.ssh/zaeem_devbox` — **`scripts/setup-gcp-prereqs.sh` generates this for you**
- Add the public key content (`cat ~/.ssh/zaeem_devbox.pub`) to the `SSH_PUBLIC_KEYS` array in your profile
- Repeat for each machine that needs access to the VM

### 4. GCS State Bucket

- One bucket per GCP project, named `<project-id>-zaeem-devbox-tf-state`
- Created automatically by `initialize.sh` — no manual step needed
- State is stored per profile at `gs://<project-id>-zaeem-devbox-tf-state/<profile-name>/`

### 5. GitHub SSH Access

- Your GitHub account must have an SSH key so the VM can clone `git@github.com:zaeemadamjee/zaeem_devbox.git` on first login
- Your local SSH agent must be running with the key loaded — `start.sh` warns early if it isn't

### 6. Update `dotfiles/gitconfig`

- Hardcoded name/email — update with your actual identity before provisioning

### 7. Tailscale (recommended)

Tailscale gives the VM a stable MagicDNS hostname (e.g. `devbox.tail1234abcd.ts.net`) that survives reprovisioning and ephemeral IP changes. It is also used by the opencode notification plugin to generate a direct link to the web UI.

1. Create a free account at [tailscale.com](https://tailscale.com)
2. Go to **Settings → Keys** and generate an **Auth key** (reusable, or one-time for a single VM)
3. Add the key to your profile's secrets file:
   ```bash
   # scripts/profiles/<name>.env
   TAILSCALE_AUTH_KEY=tskey-auth-...
   ```
4. `start.sh` copies the secret to the VM; bootstrap installs Tailscale and runs `tailscale up --authkey` automatically
5. After bootstrap, find the MagicDNS hostname in the [Tailscale admin console](https://login.tailscale.com/admin/machines) — it will look like `<instance-name>.<tailnet>.ts.net`

### 8. Pushover notifications (optional)

The `pushover-notify.js` opencode plugin fires a push notification to your phone whenever the agent becomes idle, hits an error, needs a permission grant, or asks a clarifying question. Notifications include the project name, elapsed time, last assistant message, and a direct link to the opencode web UI via Tailscale.

**Get credentials:**

1. Create an account at [pushover.net](https://pushover.net) — your **User Key** is shown on the dashboard
2. Go to **Your Applications → Create an Application** to get an **App Token**
3. Install the Pushover app on iOS or Android and log in

**Add to your secrets file:**

```bash
# scripts/profiles/<name>.env
PUSHOVER_APP_TOKEN=a1e11v...
PUSHOVER_USER_KEY=uzb29w...
```

**Customisation:**

| Variable | Default | Effect |
|---|---|---|
| `OPENCODE_NOTIFY=0` | (unset) | Disable all notifications without removing the plugin |
| `TAILSCALE_HOSTNAME` | (auto-detected) | Override the hostname if `tailscale status` is unavailable |

### 9. GCP Billing Alerts (optional but recommended)

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

# 3. (Optional) Create a secrets file for the profile
echo 'ANTHROPIC_API_KEY=sk-ant-...' > scripts/profiles/<name>.env

# 4. Run the orchestrator, select your profile, then select "initialize"
#    (handles APIs, SSH key, state bucket, and terraform apply in one go)
scripts/orchestrator.sh

# 5. After initialize completes, run the orchestrator again and select "start"
#    Bootstrap runs interactively on first login
scripts/orchestrator.sh
```

> **Note:** `initialize` is for first-time provisioning only. For subsequent wipe-and-recreate, use `reset` in the orchestrator instead.

### Reprovisioning (wipe and recreate an existing VM)

Run `scripts/orchestrator.sh`, select the profile, then select `reset`. Once complete, select `start` to reconnect.

---

## Daily Usage

```bash
# Open the interactive orchestrator — pick a profile and action
scripts/orchestrator.sh
```

The orchestrator presents a live status table of all profiles then lets you select:

| Action | Effect |
|---|---|
| `start` | Start the VM, copy secrets, and SSH in |
| `stop` | Stop the VM (disk persists, no compute charges) |
| `reset` | Wipe and recreate the VM from scratch ⚠ destructive |
| `initialize` | First-time provision (APIs, SSH key, state bucket, Terraform) |

The SSH config entry is named `devbox-<profile>` (e.g. `devbox-personal`), so you can also SSH directly after `start` has run once:

```bash
ssh devbox-personal
```

---

## Connecting from Multiple Machines

Add each machine's public key to `SSH_PUBLIC_KEYS` in the profile, then run `scripts/reset.sh --profile <name>` to apply. All keys are written to the VM's `authorized_keys` via Terraform.

Each local machine runs `scripts/start.sh --profile <name>` independently — it updates that machine's `~/.ssh/config` entry with the current ephemeral IP.

---

## Aliases (optional)

Alias the orchestrator to `devbox` for quick access from anywhere:

```bash
echo 'alias devbox="~/Documents/git/zaeem_devbox/scripts/orchestrator.sh"' >> ~/.zshrc
source ~/.zshrc
```

Then just run:

```bash
devbox
```
