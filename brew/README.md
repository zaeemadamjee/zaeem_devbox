# Dev Environment

Managed by [Homebrew](https://brew.sh/) via a `Brewfile`.

## Setup

`bootstrap.sh` handles this automatically. To run manually:

    brew bundle install --file=brew/Brewfile

## Adding packages

Search: `brew search PACKAGE_NAME`

Add a line to `brew/Brewfile`:

    brew "package-name"

Then commit the updated Brewfile.

## Updating packages

    brew upgrade
    brew bundle install --file=brew/Brewfile

## Languages included

- Node.js 22 — managed by **nvm** (installed via `bootstrap.sh`, not Brewfile)
- Python 3.12 (`python@3.12`)
- Go (latest)
- Rust (via `rustup` — run `rustup default stable` once after bootstrap)

## Notes

- Node.js is managed by nvm (`~/.nvm`), not Homebrew. To switch versions: `nvm use 20`.
- `rustup` installs the Rust toolchain manager; it does not install Rust itself.
  Run `rustup default stable` inside your shell after first login.
- `opentelemetry-collector-contrib` is installed via the `open-telemetry/opentelemetry` tap.
