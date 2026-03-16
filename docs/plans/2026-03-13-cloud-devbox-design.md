# Cloud Dev Box Design

**Date:** 2026-03-13
**Status:** Approved

## Summary

A GCP Compute Engine VM managed by Terraform, running a full dev environment via devbox, accessible over SSH with tmux for session persistence. Auto-stop on idle keeps costs low. This repo (`zaeem_devbox`) is the single home for all infra code, tool config, and dotfiles.

## Goals

- Work safely with Claude Code from any location
- Contain costs — primary concern is runaway compute/API spend
- Full dev environment matching local Mac setup, managed declaratively
- SSH + terminal workflow with tmux for session resilience

## Repository Structure

```
zaeem_devbox/
├── terraform/          # GCP VM, firewall, GCS state bucket
├── devbox/             # devbox.json — pinned tool versions
├── dotfiles/           # zsh, tmux, git, Claude Code config
└── scripts/
    ├── start.sh        # start VM, patch SSH config, connect
    └── stop.sh         # manual VM stop
```

## Infrastructure (Terraform)

**VM:**
- Machine type: `e2-standard-2` (2 vCPU, 8GB RAM)
- Boot disk: 50GB `pd-ssd` — expand later as needed
- OS: Ubuntu 24.04 LTS
- Zone: `us-central1-a`
- Ephemeral external IP (fetched by `start.sh` at connect time)

**Networking:**
- Firewall: SSH (port 22) open to 0.0.0.0/0
- Password auth disabled; SSH key auth only

**Terraform state:**
- Stored in GCS bucket (`zaeem-tf-state`)
- Survives laptop loss; enables full reprovision from scratch

## Dev Environment

**devbox** (`devbox/devbox.json`) pins all tools declaratively. One command installs everything on a fresh VM. Tools to be decided during setup interview but will include at minimum: `git`, `gh`, `zsh`, `tmux`, `nodejs`, `python`.

**dotfiles** (`dotfiles/`) cover:
- `zsh` config: prompt, aliases, history
- `tmux.conf`: key bindings, status bar, auto-attach on login
- `gitconfig`: identity and sensible defaults
- `~/.claude/`: Claude Code settings
- `bootstrap.sh`: symlinks all dotfiles into `$HOME`

**tmux session design:**
- Login shell auto-attaches to a persistent named tmux session
- Window 1: Claude Code
- Window 2: manual terminal
- Reconnecting after a dropped SSH connection resumes the exact session state

**`scripts/start.sh` workflow:**
1. `gcloud compute instances start zaeem-devbox`
2. Poll until SSH is ready
3. Fetch ephemeral IP, patch `~/.ssh/config`
4. SSH in (auto-attaches to tmux)

## Cost Controls

**Auto-stop (systemd timer on VM):**
- Runs every 10 minutes
- Powers off after 30 consecutive minutes of idle: CPU < 5% AND no active Claude Code process
- Configurable threshold

**GCP billing guardrails:**
- Budget alert at $30/month → email notification
- Hard cap at $50/month → GCP auto-disables billing

**Expected monthly cost:**
| Usage | Compute | Disk | Total |
|---|---|---|---|
| Light (~80 hrs) | ~$5 | ~$8.50 | **~$14** |
| Moderate (~160 hrs) | ~$11 | ~$8.50 | **~$20** |

Disk cost (~$8.50/mo) is fixed regardless of VM state. No static IP charge.

## Implementation Tasks

- Task #7: Terraform — GCS state bucket + VM + firewall
- Task #8: devbox environment — tool interview + devbox.json
- Task #9: Dotfiles — zsh, tmux, gitconfig, bootstrap.sh
- Task #10: Auto-stop systemd timer
- Task #11: start.sh / stop.sh scripts
- Task #12: GCP billing budget alerts
