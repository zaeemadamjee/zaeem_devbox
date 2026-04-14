# Tailscale Devbox Rigging — Design Spec

**Date:** 2026-04-13  
**Status:** Approved

## Overview

Add a `tailscale` subcommand to `devbox/bin/rigging` that installs the Tailscale daemon on the Linux devbox VM, enables it via systemd, and authenticates using `TAILSCALE_AUTH_KEY` if present in the environment. Report Tailscale status in `rigging check`.

## Scope

Changes are confined to `devbox/bin/rigging`. No changes to `bin/rigging` (macOS), Terraform, or dotfiles — Tailscale on macOS is already installed as a GUI cask (`pkgs/brew/casks`).

## Implementation

### `cmd_tailscale`

New function in `devbox/bin/rigging`, structured identically to `cmd_docker`.

**Step 1 — Install binary**  
If `tailscale` is not in PATH, run the official install script:
```bash
curl -fsSL https://tailscale.com/install.sh | sh
```
This script handles adding the apt source, importing the GPG key, and installing `tailscale` + `tailscaled` on Ubuntu 24.04. On failure, `_track_failed "tailscale install"` and return.

**Step 2 — Enable daemon**  
If `tailscaled` is not active (`systemctl is-active tailscaled`), run:
```bash
sudo systemctl enable --now tailscaled
```
On failure, `_track_failed "tailscaled daemon"`.

**Step 3 — Authenticate**  
- If `TAILSCALE_AUTH_KEY` is set and non-empty:
  ```bash
  sudo tailscale up --authkey "$TAILSCALE_AUTH_KEY" --accept-routes
  ```
  Log success or `_track_failed "tailscale auth"`.
- If `TAILSCALE_AUTH_KEY` is absent: `log_warn` that auth was skipped and instruct the user to run `sudo tailscale up` manually.

All three steps are idempotent — re-running rigging is safe.

### `cmd_all`

Add `cmd_tailscale` after `cmd_docker`:
```bash
cmd_docker
cmd_tailscale
cmd_idle
```

### `cmd_check` — Tailscale section

New section between Docker and Idle timer:
```
Tailscale
  ✓ tailscale installed
  ✓ tailscaled running
  ✓ tailscale authenticated
```

Checks:
1. `command -v tailscale` — binary present
2. `systemctl is-active tailscaled` — daemon running
3. `tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"'` — authenticated and connected

### Usage comment & `cmd_help`

Add to the usage block at the top of the file and to `cmd_help` output:
```
tailscale  Install Tailscale daemon + authenticate
```

### `TAILSCALE_AUTH_KEY`

Expected to be present in `~/.config/secrets.env`, which is sourced at login. No changes to secrets infrastructure needed. The user adds `TAILSCALE_AUTH_KEY=tskey-auth-...` to their profile's `.env` file, which gets copied to the VM by `bin/start`.

## Error Handling

- Install failure: logged, tracked in `FAILED[]`, function returns early (daemon and auth steps are skipped).
- Daemon failure: logged, tracked, auth step is skipped.
- Auth failure: logged, tracked. Does not block provision — VM is usable, just not on the tailnet.
- Missing auth key: warning only, not a failure. User can authenticate manually post-provision.

## Testing / Verification

Run `rigging check` on a provisioned VM after running `rigging tailscale`. Expect:
- All three Tailscale checks show `✓`
- `tailscale status` shows the VM's tailnet IP

On a fresh VM without `TAILSCALE_AUTH_KEY`: expect install + daemon checks to pass, auth check to fail (with warning during install, error during check).
