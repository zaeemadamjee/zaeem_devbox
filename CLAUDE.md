# Claude Instructions for zaeem_devbox

## Purpose

This repository maintains the complete, reproducible configuration needed to provision a personal devbox VM from scratch. It contains:

- **Local scripts** (`bin/`) — executables run from the local Mac (orchestrate, start, stop, reset, initialize VMs)
- **Config** (`config/`) — dotfiles symlinked into `~` by bootstrap (zshrc, aliases, nvim, tmux, etc.)
- **Devbox** (`devbox/`) — everything that runs on the VM: `bin/` (bootstrap, welcome, idle-check), `terraform/` (GCP infra), `lib/` (shared shell utils), `profiles/` (per-VM config), `idle/` (systemd units)
- **Lib** (`lib/`) — generic shared shell utilities (e.g. gum output helpers)
- **Pkgs** (`pkgs/Brewfile`) — hermetic CLI tool dependencies via Homebrew

The goal is that a fresh VM can be fully provisioned by running Terraform, SSHing in, and letting the bootstrap script run. Nothing should require manual one-off steps.

## Environment Fix Policy

**When fixing an environment or tooling issue, always capture the fix in the configuration.**

If you discover that something is broken on a fresh machine provision (missing tool, wrong version, bad PATH, missing env var, broken shell init, etc.), don't just patch it locally — encode the fix in `pkgs/Brewfile`, `devbox/bin/bootstrap`, or the relevant dotfile so the next machine provision works correctly out of the box.

Examples of what this means in practice:

- A required CLI tool is missing → add it to `pkgs/Brewfile`
- A package needs a specific version → pin it in `pkgs/Brewfile` (e.g. `brew "node@22"`)
- A post-install step is needed → add it to `devbox/bin/bootstrap`
- A shell environment variable needs to be set → add it to the appropriate dotfile in `config/`
- A dotfile is missing or misconfigured → fix the source dotfile in `config/`
- A GCP resource is missing (service account, IAM role, firewall rule, etc.) → add it to `devbox/terraform/main.tf`
- A VM configuration needs to change (attached SA, scopes, machine type, etc.) → update the `google_compute_instance` resource in Terraform

**Never recommend one-off `gcloud`, `gsutil`, or manual shell commands as the solution to an infrastructure problem.** Those fixes disappear when the VM is reprovisioned. Always encode the fix in Terraform or the bootstrap scripts so the next provision works correctly out of the box.
