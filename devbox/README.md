# devbox

GCP devbox provisioning — Terraform infra, bootstrap, and per-VM profiles.

## Orchestrator

    bin/orchestrator <command> [profile]

| Command              | Effect                                      |
|----------------------|---------------------------------------------|
| status               | Show live VM state for all profiles         |
| start <profile>      | Start VM, copy secrets, SSH in              |
| stop <profile>       | Stop VM (disk persists, no compute charges) |
| reset <profile>      | Wipe and recreate VM (destructive)          |
| initialize <profile> | First-time provision (APIs, SSH key, etc.)  |

Prerequisites: `gcloud` authenticated, GCP project with billing, SSH key in agent.

## Profiles

Each VM is defined by a file in `devbox/profiles/<name>` that sets the GCP project,
region, machine type, disk size, and repos to clone on first login.

Available profiles: `personal` (e2-standard-2, us-east4), `mini` (e2-micro, us-central1).

## Secrets

API keys and tokens go in a gitignored env file next to the profile:

    devbox/profiles/<name>.env   # never committed

`bin/start` copies this to `~/.config/secrets.env` on the VM before connecting.

## First provision

    bin/orchestrator initialize personal
    bin/orchestrator start personal

Bootstrap runs interactively on first SSH login.
