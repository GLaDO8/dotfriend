# dotfriend

A macOS CLI that turns your Mac into a version-controlled dotfiles repo — automatically.

Built with bash and [Gum](https://github.com/charmbracelet/gum) (by Charm). No compilation, no package manager needed for the tool itself.

## What it does

**`dotfriend start`** — An interactive wizard that scans your Mac, lets you pick what to back up, and generates a complete `dotfiles` repository. It detects your apps, Homebrew packages, npm globals, shell configs, editor settings, agentic tool configs, and even your Dock layout.

**`dotfriend sync`** — Keeps your repo in sync with your machine. Detects new brew packages, changed config files, and updated agent settings. Optionally commits and pushes to GitHub.

The generated repo includes a `bootstrap.sh` for brand-new Macs and an `install.sh` for full restoration — so you can go from a fresh macOS install to a fully configured machine in one command.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/GLaDO8/dotfriend/main/install.sh | bash
```

Or clone and run directly:

```bash
git clone https://github.com/GLaDO8/dotfriend.git
cd dotfriend
./dotfriend start
```

Homebrew and Gum are installed automatically if missing.

## Commands

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

### Agentic tools (selective, smart backup)
Only config files are backed up — never chat history, cache, or logs.

| Tool | What gets backed up |
|------|---------------------|
| **Claude Code** | `CLAUDE.md`, `settings.json`, `hooks/`, `rules/`, `plugins/` |
| **OpenAI Codex** | `AGENTS.md`, `RTK.md`, `CLAUDE.md`, `skills/`, `agent-docs/` |
| **Cursor** | `settings.json`, `mcp.json`, `keybindings.json`, `extensions/`, `rules/` |
| **Aider** | `.aider.conf.yml`, `.aider.model.settings.yml`, `.aiderignore` |
| **Continue.dev** | `config.json`, `config.ts`, `.prompts/` |
| **GitHub Copilot CLI** | `~/.config/github-copilot/` |
| **Zed** | `settings.json`, `keymap.json`, `themes/` |
| **Windsurf** | `settings.json`, `keybindings.json`, `extensions/` |
| **Cline** | `settings.json` |
| **Trae** | `settings.json`, `keybindings.json`, `extensions/` |

## Generated repo structure

```
dotfiles/
├── Brewfile              # taps, brews, casks, mas apps
├── install.sh            # Full restore script (phased, dry-run capable)
├── bootstrap.sh          # First-run script for brand-new Macs
├── scripts/
│   ├── validate.sh       # Post-install validation
│   ├── backup.sh         # Reverse-sync machine state back to repo
│   └── lib/              # Shared helpers
├── config/               # App configs symlinked to ~/.config/
├── zsh/                  # .zshrc, plugins
├── vscode/               # settings.json, extensions.txt
├── cursor/               # settings.json, keybindings.json, extensions.txt
├── claude/               # CLAUDE.md, settings.json, hooks/, rules/
├── codex/                # AGENTS.md, RTK.md, skills/
├── agents/               # Shared agent skills and docs
├── dock/
│   └── dock-apps.txt     # Restorable Dock layout
├── .gitignore
└── locations.md          # Auto-generated config location reference
```

## Requirements

- macOS (Apple Silicon or Intel)
- bash 4+

`dotfriend` automatically installs **Homebrew** and **Gum** if they're not present. Optional enhancements come from `jq`, `gh`, `mas`, and `npm` if you have them.

## Why dotfriend?

Most dotfiles tools expect you to hand-write your config. `dotfriend` starts from your *actual* machine state and builds the repo for you. It's designed for people who:

- Want a dotfiles repo but haven't gotten around to making one
- Frequently set up new Macs and want a one-command restore
- Use multiple agentic AI tools and want their configs versioned
- Prefer bash + Gum over compiled binaries for transparency and hackability

## License

MIT
