# dotfriend

Automatically turn your Mac setup into a restorable dotfiles repo.

`dotfriend` scans your Mac, lets you choose what to keep, and generates a Git-backed repo that can restore your shell, apps, packages, editor settings, AI coding tool configs, hooks, skills, and agent instructions on a new Mac.

Back up your Mac configuration, generate a restorable dotfiles repo, and push it to GitHub.

## What are dotfiles?

Dotfiles are the hidden config files and folders that make your tools feel like yours: shell settings, Git config, editor preferences, package lists, app configs, and AI coding agent setup.

## dotfriend vs. Time Machine

Time Machine backs up your whole Mac. `dotfriend` backs up your setup recipe.

Use Time Machine to recover files and system snapshots. Use `dotfriend` to recreate your developer environment on a fresh Mac or keep your config versioned in Git.

## What it does

**`dotfriend start`** — An interactive wizard that scans your Mac, lets you pick what to back up, and generates a complete `dotfiles` repository. It detects your apps, Homebrew packages, npm globals, shell configs, editor settings, AI coding tool configs, and even your Dock layout.

**`dotfriend sync`** — Keeps your repo in sync with your machine. Detects new brew packages, changed config files, and updated agent settings. Optionally commits and pushes to GitHub.

The generated repo includes a `bootstrap.sh` for brand-new Macs and an `install.sh` for full restoration — so you can go from a fresh macOS install to a fully configured machine in one command.

## Installation

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

| Command | Description |
|---------|-------------|
| `dotfriend start` | Interactive wizard. Scans your Mac and generates the dotfiles repo. |
| `dotfriend start --dry-run` | Preview what would be generated without writing files. |
| `dotfriend sync` | Incremental sync. Update the repo with changes from your machine. |
| `dotfriend sync --dry-run` | Preview what would change without applying. |
| `dotfriend sync --no-commit` | Apply changes but don't commit. |
| `dotfriend sync --quick` | Non-interactive sync. Skip prompts and commit with a default message. |
| `dotfriend --help` | Show usage. |
| `dotfriend --version` | Show version. |

## What gets backed up

### System & packages
- **Homebrew** — taps, formulae, casks, Mac App Store apps (via `mas`)
- **npm** — globally installed packages
- **Dock layout** — app list (restorable via `dockutil`)

### Config files
- Shell configs (`.zshrc`, `.bashrc`, `.gitconfig`, `.tmux.conf`, etc.)
- `~/.config/` directories for detected apps
- Editor settings (VS Code, Cursor — including extensions)

### AI coding tools and agent configs
Back up the setup that makes AI coding tools behave the way you expect: agent instructions, reusable skills, hooks, rules, MCP/server configs, plugins, and editor integration settings.

Only config files are backed up — never chat history, caches, or logs.

Examples include `AGENTS.md`, `CLAUDE.md`, `settings.json`, `mcp.json`, `hooks/`, `rules/`, `skills/`, `plugins/`, and tool-specific config under `~/.config`.

Back up configs from tools like Claude Code, OpenAI Codex, Cursor, opencode, Windsurf, Aider, Continue.dev, GitHub Copilot CLI, Zed, Cline, and Trae.

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

- Want a dotfiles repo but haven't gotten around to making one
- Frequently set up new Macs and want a one-command restore
- Use multiple AI coding tools and want their configs versioned
- Prefer bash + Gum over compiled binaries for transparency and hackability

## License

MIT
