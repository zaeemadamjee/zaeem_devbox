# zaeem

Personal dev environment — dotfiles, language toolchains, and GCP devbox provisioning.

---

## Mac

```bash
curl -fsSL https://raw.githubusercontent.com/zaeemadamjee/zaeem/main/bin/bootstrap | bash
```

Installs Xcode CLI tools, clones the repo, sets up Homebrew packages, dotfiles, and language toolchains. Open a new shell when done.

<details>
<summary>More details</summary>

To check status at any time:

```bash
~/workspace/zaeem/bin/setup-mac check
```

`bootstrap` clones the repo to `~/workspace/zaeem`, then runs `setup-mac` to install Homebrew packages, stow dotfiles, write shell init, and install language toolchains and tools.

</details>

---

## Devbox

```bash
bin/orchestrator <command> [profile]
```

| Command | Effect |
|---|---|
| `status` | Show live VM state for all profiles |
| `start <profile>` | Start VM, copy secrets, SSH in |
| `stop <profile>` | Stop VM (disk persists, no compute charges) |
| `reset <profile>` | Wipe and recreate VM ⚠ destructive |
| `initialize <profile>` | First-time provision (APIs, SSH key, state bucket, Terraform) |

<details>
<summary>Prerequisites</summary>

- `gcloud` CLI authenticated (`gcloud auth login`)
- A GCP project with billing enabled
- SSH key loaded in agent (`ssh-add ~/.ssh/zaeem`)

</details>

<details>
<summary>Profiles</summary>

Each VM is defined by a profile in `devbox/profiles/<name>`. A profile sets the GCP project, region, machine type, disk size, SSH keys, and which repos to clone on first login.

```bash
# Create a new profile by copying an existing one
cp devbox/profiles/personal devbox/profiles/myproject
# Edit devbox/profiles/myproject — update GCP_PROJECT, instance name, etc.
```

Secrets (API keys, tokens) go in a gitignored `.env` file next to the profile:

```bash
# devbox/profiles/personal.env  (never committed)
ANTHROPIC_API_KEY=sk-ant-...
```

`bin/start` copies this to `~/.config/secrets.env` on the VM before connecting.

</details>

<details>
<summary>First provision</summary>

```bash
bin/orchestrator initialize personal
# when complete, start automatically prompts — or:
bin/orchestrator start personal
```

Bootstrap runs interactively on first SSH login.

</details>
