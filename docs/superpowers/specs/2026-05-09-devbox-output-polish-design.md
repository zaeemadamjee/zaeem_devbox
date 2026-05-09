# Design: devbox start output polish + progress bar

**Date:** 2026-05-09  
**Status:** Approved

---

## Goal

Clean up the `devbox/bin/start` output so it is visually uniform and informative.
Specifically:

1. Suppress leaking `gcloud` output on success; show it on failure.
2. Replace static "Waiting…" lines with an animated progress bar.
3. Suppress the raw OpenSSH `Warning: Permanently added…` message on final connect.

---

## Changes

### 1. `lib/log.sh` — add progress bar primitives

Add two new functions:

**`log_progress_bar <elapsed_s> <max_s> <label>`**

Renders a 20-character block-fill bar on the current line using `\r` to overwrite
in-place each time it is called.

```
  Waiting for SSH    [████████░░░░░░░░░░░░] 40s / 150s
```

- Fill character: `█`  Empty character: `░`
- Fill proportion: `min(elapsed / max, 1.0)` (capped at full)
- Color: green for filled blocks, dim for empty — both reset after
- TTY-gated: when stdout is not a TTY (pipe, CI), falls back to a plain `echo`
  on the first call only (no repeated lines), then no-ops on subsequent calls.

**`log_progress_bar_clear`**

Emits a carriage-return + spaces + carriage-return sequence to blank the current
line before a `log_ok` or `log_error` is printed, so the bar does not leave residue.
No-op when stdout is not a TTY.

---

### 2. `devbox/lib/ssh.sh` — integrate progress bar into wait functions

**`ssh_wait_ready`**

Accumulate elapsed time across both polling phases (IP wait + SSH wait).
Call `log_progress_bar $elapsed 150 "Waiting for SSH"` once per loop iteration
(every 5 s) to update the bar in-place. Call `log_progress_bar_clear` before
returning (success or failure) so the caller's `log_ok`/`log_error` lands cleanly.

**`ssh_wait_startup`**

Same pattern: `log_progress_bar $elapsed 150 "Waiting for startup script"`,
`log_progress_bar_clear` before returning.

The callers (`devbox/bin/start`) keep their existing `log_info` line before the
call and their `log_ok`/`log_error` line after — no changes needed there.

---

### 3. `devbox/bin/start` — capture gcloud output

**`gcloud compute instances start`** call:

Capture stdout+stderr to a temp file. On success: delete temp file silently.
On failure: pipe each captured line through `log_dim`, then exit 1.

```bash
_gcloud_tmp=$(mktemp)
trap 'rm -f "$_gcloud_tmp"' RETURN
if ! gcloud compute instances start "$GCP_INSTANCE_NAME" \
       --zone="$GCP_ZONE" --project="$GCP_PROJECT" --quiet \
       >"$_gcloud_tmp" 2>&1; then
  while IFS= read -r line; do log_dim "  $line"; done < "$_gcloud_tmp"
  exit 1
fi
```

---

### 4. `devbox/bin/stop` — same gcloud capture pattern

Apply identical capture-on-failure pattern to `gcloud compute instances stop`
for consistency.

---

### 5. `devbox/bin/start` — suppress SSH known_hosts warning

Add `-o LogLevel=ERROR` to the final interactive SSH call:

```bash
ssh_retry 3 5 ssh -A -o LogLevel=ERROR "$SSH_HOST"
```

---

## Files touched

| File | Change |
|------|--------|
| `lib/log.sh` | Add `log_progress_bar`, `log_progress_bar_clear` |
| `devbox/lib/ssh.sh` | Integrate progress bar into `ssh_wait_ready`, `ssh_wait_startup` |
| `devbox/bin/start` | Capture gcloud output; add `LogLevel=ERROR` to final ssh |
| `devbox/bin/stop` | Capture gcloud output |

---

## Expected output (happy path)

```
▸ VM (zaeem-devbox)
  Starting zaeem-devbox...
  ✓ Instance started
  Waiting for SSH    [████████░░░░░░░░░░░░] 40s / 150s   ← live, overwrites
  ✓ VM is up at 104.154.72.243
  Opening SSH master connection...
  ✓ Master connection established
  Waiting for startup script   [████░░░░░░░░░░░░░░░░] 20s / 150s   ← live
  ✓ Startup script complete

▸ Setup
  Copying secrets (personal.env)...
  ✓ Secrets copied to ~/.config/secrets.env
  Installing Ghostty terminfo...
  ✓ Ghostty terminfo installed

▸ SSH config
  ✓ Updated devbox-personal → 104.154.72.243

  Connecting to devbox-personal...

            .-/+oossssoo+/-.               zaeem@zaeem-devbox...
```

## Expected output (gcloud failure)

```
▸ VM (zaeem-devbox)
  Starting zaeem-devbox...
  ERROR: (gcloud.compute.instances.start) ...
  ✗ Could not reach VM over SSH after polling
```

---

## Non-goals

- No changes to `rigging` scripts (the progress bar is available there via `lib/log.sh`
  if needed later, but no rigging scripts are touched in this change).
- No changes to `devbox/bin/initialize` — it runs Terraform interactively and
  the noisy output there is intentional.
- No changes to the banner or section formatting — those are already consistent.
