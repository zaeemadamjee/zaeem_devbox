# devbox output polish + progress bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean up `devbox/bin/start` output so it is visually uniform: suppress leaking gcloud output (show only on failure), animate wait periods with a progress bar, and eliminate the raw OpenSSH known_hosts warning.

**Architecture:** Add `log_progress_bar` / `log_progress_bar_clear` to the shared `lib/log.sh` logging library. Integrate those functions into the two SSH wait loops in `devbox/lib/ssh.sh`. Capture gcloud subprocess output in `devbox/bin/start` and `devbox/bin/stop`, showing it only on failure. Add `-o LogLevel=ERROR` to the final interactive SSH call.

**Tech Stack:** Bash, ANSI escape codes, standard POSIX utilities (`printf`, `mktemp`).

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/log.sh` | Modify | Add `log_progress_bar` and `log_progress_bar_clear` |
| `devbox/lib/ssh.sh` | Modify | Drive progress bar inside `ssh_wait_ready` and `ssh_wait_startup` |
| `devbox/bin/start` | Modify | Capture gcloud output; add `LogLevel=ERROR` to final ssh |
| `devbox/bin/stop` | Modify | Capture gcloud output |

---

### Task 1: Add `log_progress_bar` and `log_progress_bar_clear` to `lib/log.sh`

**Files:**
- Modify: `lib/log.sh`

- [ ] **Step 1: Read the current end of `lib/log.sh` to confirm insertion point**

  The file currently ends at line 57 with `log_dim`. Append below it.

- [ ] **Step 2: Add the two new functions**

  Append the following block to `lib/log.sh` (after the existing `log_dim` function):

  ```bash
  # Progress bar — renders/updates in-place using \r.
  # Usage: log_progress_bar <elapsed_s> <max_s> <label>
  #
  # On a TTY: overwrites the current line each call. Call log_progress_bar_clear
  # before printing a log_ok/log_error so the bar line is fully erased.
  # Off-TTY (pipe/CI): prints a single plain line on the first call, then no-ops.
  _LOG_PROGRESS_PRINTED=0
  log_progress_bar() {
    local elapsed="$1" max="$2" label="$3"
    local width=20

    # Compute fill (integer arithmetic; cap at width)
    local fill=$(( elapsed * width / (max > 0 ? max : 1) ))
    (( fill > width )) && fill=$width
    local empty=$(( width - fill ))

    local bar_filled bar_empty
    bar_filled=$(printf '%0.s█' $(seq 1 $fill))
    bar_empty=$(printf '%0.s░' $(seq 1 $empty))

    # Elapsed / max display (show as integers)
    local time_str="${elapsed}s / ${max}s"

    if [[ -t 1 ]]; then
      # TTY: overwrite the current line
      printf "\r  %-30s ${_LOG_DIM}[${_LOG_RESET}${_LOG_GREEN}%s${_LOG_RESET}${_LOG_DIM}%s]${_LOG_RESET} %s   " \
        "$label" "$bar_filled" "$bar_empty" "$time_str"
    else
      # Non-TTY: print once, then silence
      if [[ "$_LOG_PROGRESS_PRINTED" -eq 0 ]]; then
        printf "  %s [%s%s] %s\n" "$label" "$bar_filled" "$bar_empty" "$time_str"
        _LOG_PROGRESS_PRINTED=1
      fi
    fi
  }

  # Clears the progress bar line (TTY only) so the next log_ok/log_error
  # lands on a clean line.
  log_progress_bar_clear() {
    if [[ -t 1 ]]; then
      printf "\r%-80s\r" ""
    fi
    _LOG_PROGRESS_PRINTED=0
  }
  ```

- [ ] **Step 3: Manual smoke-test the bar renders correctly**

  Run in a shell (from repo root):

  ```bash
  source lib/log.sh
  for i in 0 30 60 90 120 150; do
    log_progress_bar $i 150 "Waiting for SSH"
    sleep 0.3
  done
  log_progress_bar_clear
  log_ok "VM is up at 1.2.3.4"
  ```

  Expected: bar fills from empty to full across 6 frames, then clears and `✓ VM is up at 1.2.3.4` prints on a clean line.

- [ ] **Step 4: Commit**

  ```bash
  git add lib/log.sh
  git commit -m "feat(log): add log_progress_bar and log_progress_bar_clear"
  ```

---

### Task 2: Integrate progress bar into `ssh_wait_ready`

**Files:**
- Modify: `devbox/lib/ssh.sh` (function `ssh_wait_ready`, lines 59–88)

- [ ] **Step 1: Read `ssh_wait_ready` in `devbox/lib/ssh.sh` (lines 59–88)**

  Understand the two-phase polling structure before editing.

- [ ] **Step 2: Rewrite `ssh_wait_ready` to track elapsed time and call the progress bar**

  Replace the entire `ssh_wait_ready` function body with:

  ```bash
  ssh_wait_ready() {
    local instance="$1" zone="$2" project="$3" user="$4" out="$5"
    local max_s=150
    local elapsed=0

    # Phase 1: wait for external IP (up to 15 polls × 5 s = 75 s)
    local ip=""
    local i
    for i in $(seq 1 15); do
      log_progress_bar "$elapsed" "$max_s" "Waiting for SSH"
      ip=$(gcloud compute instances describe "$instance" \
        --zone="$zone" --project="$project" \
        --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || true)
      [[ -n "$ip" ]] && break
      sleep 5
      elapsed=$(( elapsed + 5 ))
    done

    if [[ -z "$ip" ]]; then
      log_progress_bar_clear
      return 1
    fi

    # Phase 2: wait for SSH (up to 30 polls × 5 s = 150 s, continuing elapsed)
    _ssh_opts_init
    for i in $(seq 1 30); do
      log_progress_bar "$elapsed" "$max_s" "Waiting for SSH"
      if ssh "${SSH_OPTS[@]}" "${user}@${ip}" true 2>/dev/null; then
        echo "$ip" > "$out"
        log_progress_bar_clear
        return 0
      fi
      sleep 5
      elapsed=$(( elapsed + 5 ))
    done

    log_progress_bar_clear
    return 1
  }
  ```

- [ ] **Step 3: Verify the function signature and callers are unchanged**

  The callers in `devbox/bin/start` call:
  ```bash
  ssh_wait_ready "$GCP_INSTANCE_NAME" "$GCP_ZONE" "$GCP_PROJECT" "$SSH_USER" "$IP_FILE"
  ```
  The new function still accepts the same 5 arguments — no caller changes needed.

- [ ] **Step 4: Commit**

  ```bash
  git add devbox/lib/ssh.sh
  git commit -m "feat(ssh): add progress bar to ssh_wait_ready"
  ```

---

### Task 3: Integrate progress bar into `ssh_wait_startup`

**Files:**
- Modify: `devbox/lib/ssh.sh` (function `ssh_wait_startup`, lines 98–108)

- [ ] **Step 1: Read `ssh_wait_startup` in `devbox/lib/ssh.sh` (lines 98–108)**

- [ ] **Step 2: Rewrite `ssh_wait_startup` to track elapsed time and call the progress bar**

  Replace the entire `ssh_wait_startup` function body with:

  ```bash
  ssh_wait_startup() {
    local user="$1" ip="$2"
    local max_s=150
    local elapsed=0
    local i
    for i in $(seq 1 30); do
      log_progress_bar "$elapsed" "$max_s" "Waiting for startup script"
      if _ssh_run "$user" "$ip" "sudo test -f /var/lib/startup-complete" 2>/dev/null; then
        log_progress_bar_clear
        return 0
      fi
      sleep 5
      elapsed=$(( elapsed + 5 ))
    done
    log_progress_bar_clear
    return 1
  }
  ```

- [ ] **Step 3: Verify callers unchanged**

  `devbox/bin/start` calls:
  ```bash
  ssh_wait_startup "$SSH_USER" "$IP"
  ```
  Same 2-argument signature — no caller changes needed.

- [ ] **Step 4: Commit**

  ```bash
  git add devbox/lib/ssh.sh
  git commit -m "feat(ssh): add progress bar to ssh_wait_startup"
  ```

---

### Task 4: Capture gcloud output in `devbox/bin/start`

**Files:**
- Modify: `devbox/bin/start` (lines 41–43)

- [ ] **Step 1: Read the gcloud start block in `devbox/bin/start` (lines 39–44)**

  Current code:
  ```bash
  log_info "Starting $GCP_INSTANCE_NAME..."
  gcloud compute instances start "$GCP_INSTANCE_NAME" \
    --zone="$GCP_ZONE" --project="$GCP_PROJECT" --quiet
  log_ok "Instance started"
  ```

- [ ] **Step 2: Replace with capture-on-failure pattern**

  ```bash
  log_info "Starting $GCP_INSTANCE_NAME..."
  _gcloud_tmp=$(mktemp)
  if ! gcloud compute instances start "$GCP_INSTANCE_NAME" \
         --zone="$GCP_ZONE" --project="$GCP_PROJECT" --quiet \
         >"$_gcloud_tmp" 2>&1; then
    while IFS= read -r _line; do log_dim "  $_line"; done < "$_gcloud_tmp"
    rm -f "$_gcloud_tmp"
    exit 1
  fi
  rm -f "$_gcloud_tmp"
  log_ok "Instance started"
  ```

  Note: the existing `trap 'rm -f "$IP_FILE"' EXIT` at line 47 does not cover `$_gcloud_tmp` — the explicit `rm -f` calls above handle cleanup on both success and failure paths.

- [ ] **Step 3: Add `-o LogLevel=ERROR` to the final interactive SSH call**

  Current last line of `devbox/bin/start` (line 176):
  ```bash
  ssh_retry 3 5 ssh -A "$SSH_HOST"
  ```

  Replace with:
  ```bash
  ssh_retry 3 5 ssh -A -o LogLevel=ERROR "$SSH_HOST"
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add devbox/bin/start
  git commit -m "fix(start): suppress gcloud output on success; suppress SSH known_hosts warning"
  ```

---

### Task 5: Capture gcloud output in `devbox/bin/stop`

**Files:**
- Modify: `devbox/bin/stop` (lines 20–22)

- [ ] **Step 1: Read the gcloud stop block in `devbox/bin/stop` (lines 20–22)**

  Current code:
  ```bash
  log_info "Stopping $GCP_INSTANCE_NAME (profile: $PROFILE_NAME)..."
  gcloud compute instances stop "$GCP_INSTANCE_NAME" \
    --zone="$GCP_ZONE" --project="$GCP_PROJECT" --quiet

  log_ok "$GCP_INSTANCE_NAME stopped"
  ```

- [ ] **Step 2: Replace with capture-on-failure pattern**

  ```bash
  log_info "Stopping $GCP_INSTANCE_NAME (profile: $PROFILE_NAME)..."
  _gcloud_tmp=$(mktemp)
  if ! gcloud compute instances stop "$GCP_INSTANCE_NAME" \
         --zone="$GCP_ZONE" --project="$GCP_PROJECT" --quiet \
         >"$_gcloud_tmp" 2>&1; then
    while IFS= read -r _line; do log_dim "  $_line"; done < "$_gcloud_tmp"
    rm -f "$_gcloud_tmp"
    exit 1
  fi
  rm -f "$_gcloud_tmp"
  log_ok "$GCP_INSTANCE_NAME stopped"
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add devbox/bin/stop
  git commit -m "fix(stop): suppress gcloud output on success, show on failure"
  ```

---

### Task 6: End-to-end verification

- [ ] **Step 1: Run a full `devbox start` against a stopped VM**

  ```bash
  devbox start personal
  ```

  Expected output (no raw gcloud lines, no OpenSSH warning, animated progress bars):
  ```
  ▸ VM (zaeem-devbox)
    Starting zaeem-devbox...
    ✓ Instance started
    Waiting for SSH    [████████░░░░░░░░░░░░] 40s / 150s
    ✓ VM is up at <IP>
    Opening SSH master connection...
    ✓ Master connection established
    Waiting for startup script   [████░░░░░░░░░░░░░░░░] 20s / 150s
    ✓ Startup script complete

  ▸ Setup
    Copying secrets (personal.env)...
    ✓ Secrets copied to ~/.config/secrets.env
    Installing Ghostty terminfo...
    ✓ Ghostty terminfo installed

  ▸ SSH config
    ✓ Updated devbox-personal → <IP>

    Connecting to devbox-personal...

              .-/+oossssoo+/-.               zaeem@zaeem-devbox...
  ```

  Verify: no raw gcloud lines appear, no `Warning: Permanently added` line appears.

- [ ] **Step 2: Run `devbox stop`**

  ```bash
  devbox stop personal
  ```

  Expected: only formatted lines, no raw gcloud output.
