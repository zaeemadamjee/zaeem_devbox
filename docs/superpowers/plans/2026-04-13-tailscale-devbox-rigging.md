# Tailscale Devbox Rigging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `tailscale` subcommand to `devbox/bin/rigging` that installs the Tailscale daemon on the Linux devbox VM, enables it via systemd, and authenticates using `TAILSCALE_AUTH_KEY` if present; report status in `rigging check`.

**Architecture:** A single new function `cmd_tailscale` is added to `devbox/bin/rigging`, following the exact pattern of `cmd_docker`. It is called from `cmd_all` and its three checks (binary, daemon, authenticated) are added to `cmd_check`. No new files are created.

**Tech Stack:** Bash, systemd, Tailscale official install script (`https://tailscale.com/install.sh`), `tailscale status --json`.

---

### Task 1: Add `cmd_tailscale` function

**Files:**
- Modify: `devbox/bin/rigging`

- [ ] **Step 1: Open `devbox/bin/rigging` and locate the end of `cmd_docker` (around line 275)**

The function ends at the closing `}` after the docker group block. Insert `cmd_tailscale` immediately after it, before `cmd_idle`.

- [ ] **Step 2: Add `cmd_tailscale` function after `cmd_docker`**

Insert the following block after the closing `}` of `cmd_docker` and before `cmd_idle`:

```bash
cmd_tailscale() {
  log_section "Tailscale"

  if command -v tailscale &>/dev/null; then
    log_info "Tailscale: already installed"
  else
    log_info "Tailscale: installing..."
    local _ts_log
    _ts_log="$(mktemp)"
    if curl -fsSL https://tailscale.com/install.sh | sh >"$_ts_log" 2>&1; then
      log_ok "Tailscale installed"
    else
      log_error "Tailscale install failed — see log: $_ts_log"
      cat "$_ts_log" >&2
      _track_failed "tailscale install"
      return
    fi
    rm -f "$_ts_log"
  fi

  if systemctl is-active tailscaled &>/dev/null; then
    log_info "tailscaled: already running"
  else
    log_info "tailscaled: enabling..."
    sudo systemctl enable --now tailscaled \
      && log_ok "tailscaled running" \
      || { log_warn "tailscaled failed to start"; _track_failed "tailscaled daemon"; return; }
  fi

  if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
    log_info "Tailscale: authenticating..."
    sudo tailscale up --authkey "$TAILSCALE_AUTH_KEY" --accept-routes \
      && log_ok "Tailscale authenticated" \
      || { log_warn "Tailscale auth failed"; _track_failed "tailscale auth"; }
  else
    log_warn "TAILSCALE_AUTH_KEY not set — skipping auth. Run 'sudo tailscale up' manually."
  fi
}
```

- [ ] **Step 3: Verify the file is valid bash**

```bash
bash -n devbox/bin/rigging
```

Expected: no output (exit 0).

- [ ] **Step 4: Commit**

```bash
git add devbox/bin/rigging
git commit -m "feat(devbox): add cmd_tailscale to rigging"
```

---

### Task 2: Wire `cmd_tailscale` into `cmd_all`

**Files:**
- Modify: `devbox/bin/rigging`

- [ ] **Step 1: Find `cmd_all` (around line 414)**

It currently reads:
```bash
cmd_all() {
  log_banner "rigging"
  cmd_install
  cmd_link
  cmd_langs
  cmd_tools
  cmd_docker
  cmd_idle
  cmd_repos
  _secrets_check
  _summary
}
```

- [ ] **Step 2: Add `cmd_tailscale` after `cmd_docker`**

Replace the body so it reads:
```bash
cmd_all() {
  log_banner "rigging"
  cmd_install
  cmd_link
  cmd_langs
  cmd_tools
  cmd_docker
  cmd_tailscale
  cmd_idle
  cmd_repos
  _secrets_check
  _summary
}
```

- [ ] **Step 3: Verify**

```bash
bash -n devbox/bin/rigging
```

Expected: no output (exit 0).

- [ ] **Step 4: Commit**

```bash
git add devbox/bin/rigging
git commit -m "feat(devbox): call cmd_tailscale from cmd_all"
```

---

### Task 3: Add Tailscale section to `cmd_check`

**Files:**
- Modify: `devbox/bin/rigging`

- [ ] **Step 1: Find the Docker section in `cmd_check` (around line 388)**

It currently ends with:
```bash
  log_section "Idle timer"
```

- [ ] **Step 2: Insert a Tailscale section between Docker and Idle timer**

Replace:
```bash
  log_section "Idle timer"
```

With:
```bash
  log_section "Tailscale"
  command -v tailscale &>/dev/null \
    && _chk "tailscale installed" ok || _chk "tailscale installed" fail
  systemctl is-active tailscaled &>/dev/null \
    && _chk "tailscaled running" ok || _chk "tailscaled running" fail
  tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"' \
    && _chk "tailscale authenticated" ok || _chk "tailscale authenticated" fail

  log_section "Idle timer"
```

- [ ] **Step 3: Verify**

```bash
bash -n devbox/bin/rigging
```

Expected: no output (exit 0).

- [ ] **Step 4: Commit**

```bash
git add devbox/bin/rigging
git commit -m "feat(devbox): add tailscale status checks to cmd_check"
```

---

### Task 4: Update usage comment and `cmd_help`

**Files:**
- Modify: `devbox/bin/rigging`

- [ ] **Step 1: Update the usage comment at the top of the file**

Find the existing usage block (lines 4–17):
```bash
# Commands:
#   all      Run everything  (default)
#   install  Homebrew + brew bundle
#   link     Stow dotfiles + .hushlogin
#   langs    Language toolchains via pkgs/lang/*
#   tools    Claude code, opencode, TPM, atuin, tldr
#   docker   Docker Engine + daemon + group membership
#   idle     Systemd idle timer
#   repos    Clone workspace repos from GCE metadata
#   check    Print ✓/✗ status without modifying anything
#   help     Show this message
```

Replace with:
```bash
# Commands:
#   all       Run everything  (default)
#   install   Homebrew + brew bundle
#   link      Stow dotfiles + .hushlogin
#   langs     Language toolchains via pkgs/lang/*
#   tools     Claude code, opencode, TPM, atuin, tldr
#   docker    Docker Engine + daemon + group membership
#   tailscale Install Tailscale daemon + authenticate
#   idle      Systemd idle timer
#   repos     Clone workspace repos from GCE metadata
#   check     Print ✓/✗ status without modifying anything
#   help      Show this message
```

- [ ] **Step 2: Update `cmd_help` output**

Find the heredoc in `cmd_help`:
```bash
    docker   Docker Engine + daemon + group membership
    idle     Systemd idle timer
```

Replace with:
```bash
    docker    Docker Engine + daemon + group membership
    tailscale Install Tailscale daemon + authenticate
    idle      Systemd idle timer
```

- [ ] **Step 3: Update the `main` dispatch to include `tailscale` in the profile-required list and the case statement**

Find:
```bash
  case "$cmd" in
    all|install|link|langs|tools|docker|idle|repos)
      _resolve_profile
      ;;
  esac
```

Replace with:
```bash
  case "$cmd" in
    all|install|link|langs|tools|docker|tailscale|idle|repos)
      _resolve_profile
      ;;
  esac
```

Find:
```bash
    docker)  log_banner "rigging docker";  cmd_docker;  _summary ;;
    idle)    log_banner "rigging idle";    cmd_idle;    _summary ;;
```

Replace with:
```bash
    docker)    log_banner "rigging docker";    cmd_docker;    _summary ;;
    tailscale) log_banner "rigging tailscale"; cmd_tailscale; _summary ;;
    idle)      log_banner "rigging idle";      cmd_idle;      _summary ;;
```

- [ ] **Step 4: Verify**

```bash
bash -n devbox/bin/rigging
```

Expected: no output (exit 0).

- [ ] **Step 5: Commit**

```bash
git add devbox/bin/rigging
git commit -m "feat(devbox): add tailscale to help text and main dispatch"
```

---

### Task 5: Final verification

- [ ] **Step 1: Run shellcheck if available**

```bash
shellcheck devbox/bin/rigging 2>/dev/null || echo "shellcheck not available — skip"
```

Expected: no errors (or "shellcheck not available").

- [ ] **Step 2: Confirm all four changes are present**

```bash
grep -n "tailscale" devbox/bin/rigging
```

Expected output should include lines for:
- Usage comment (`#   tailscale`)
- `cmd_tailscale()` function definition
- `cmd_all` body (`cmd_tailscale`)
- `cmd_check` section (`log_section "Tailscale"` and three `_chk` calls)
- `main` profile case (`tailscale`)
- `main` dispatch case (`tailscale)`)
- `cmd_help` heredoc (`tailscale`)

- [ ] **Step 3: Confirm the file is still valid bash**

```bash
bash -n devbox/bin/rigging && echo "OK"
```

Expected: `OK`
