# dotfriend

[![npm version](https://img.shields.io/npm/v/dotfriend.svg)](https://www.npmjs.com/package/dotfriend) [![License](https://img.shields.io/npm/l/dotfriend.svg)](https://www.npmjs.com/package/dotfriend)

Back up your Mac configuration, generate a restorable dotfiles repo, and push it to GitHub.

`dotfriend` scans the machine you already use, helps you choose which configs and packages to track, then writes a dotfiles repo with install, bootstrap, validation, and backup scripts.

## Quick start

```bash
npx dotfriend start
```

Or install it globally:

```bash
npm install -g dotfriend
dotfriend start
```

## How it works

1. `dotfriend start` scans your Mac.
2. You choose which configs, packages, apps, and tools to track.
3. `dotfriend` generates a dotfiles repo.
4. `dotfriend` can create and push the repo to GitHub.
5. `dotfriend sync` keeps the repo updated as your machine changes.

The generated repo is meant to be useful in both directions: restore a new Mac from your repo, then sync later machine changes back into the repo.

## Features

- Interactive macOS discovery
- Homebrew taps, formulae, casks, and Mac App Store apps
- Global npm package backup
- Shell, Git, editor, and app config backup
- Supported AI coding tool config backup
- Dock layout capture
- Generated install, bootstrap, validate, and backup scripts
- Optional GitHub repo creation and push
- Incremental sync for future changes

## Commands

| Command | Description |
| --- | --- |
| `dotfriend start` | Run the first-time wizard and generate a dotfiles repo. |
| `dotfriend start --dry-run` | Preview generation without writing files. |
| `dotfriend sync` | Update an existing generated repo from the current machine. |
| `dotfriend sync --dry-run` | Preview sync changes without applying them. |
| `dotfriend sync --no-commit` | Apply sync changes without creating a commit. |
| `dotfriend sync --quick` | Run a non-interactive sync with default choices. |
| `dotfriend --help` | Show CLI help. |
| `dotfriend --version` | Show the installed version. |

## What gets captured

`dotfriend` focuses on reproducible setup state:

- Homebrew taps, formulae, casks, and Mac App Store apps when available
- Global npm packages
- Common shell and Git dotfiles
- App config directories under `~/.config`
- VS Code and Cursor settings and extensions
- Supported AI coding tool configuration files
- Dock layout

## What is not captured yet

`dotfriend` intentionally avoids secrets and transient state. It does not currently capture:

- Secrets, passwords, SSH keys, API tokens, or keychain items
- Full application data, databases, documents, downloads, photos, or media libraries
- Browser profiles, cookies, sessions, or history
- Chat histories, agent run logs, caches, and other transient AI tool state
- macOS system defaults beyond the tracked app, package, config, and Dock state
- App-specific settings that live outside common config locations unless `dotfriend` knows how to detect them

## Generated repo

A generated repo includes:

```txt
dotfiles/
  Brewfile
  install.sh
  bootstrap.sh
  scripts/
    backup.sh
    validate.sh
  .dotfriend/
```

- `Brewfile` for Homebrew packages and apps
- `install.sh` for restoring onto an existing Mac
- `bootstrap.sh` for first-run setup on a new Mac
- `scripts/backup.sh` for syncing machine state back into the repo
- `scripts/validate.sh` for checking whether expected tools and files are present
- `.dotfriend/` metadata used by future syncs

## Requirements

- macOS
- Node.js 14 or newer for the npm wrapper
- Bash 4 or newer

`dotfriend` bootstraps its runtime dependencies before running `start` or `sync`, including Homebrew and Gum when needed.

## License

MIT
