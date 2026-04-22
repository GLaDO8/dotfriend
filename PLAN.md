# dotfriend — Refined Plan (v1)

## 1. Overview

dotfriend is a bash-based CLI tool that uses [Gum](https://github.com/charmbracelet/gum) (by Charm) for its TUI. It helps macOS users (starting with macOS Tahoe) generate a complete, version-controlled `dotfiles` repository from their current machine state. The generated repo includes a `bootstrap.sh` for first-run setup on a new Mac and an `install.sh` for full restoration, closely following the patterns established in the existing `local-documents/dotfiles/` repo.

**Design principle:** Maximize compatibility and ease of distribution. Anyone with bash and Gum can run it. No compilation, no package managers needed for the tool itself.

---

## 2. Tooling Decision

- **Implementation language:** Bash (orchestration scripts)
- **TUI framework:** [Gum](https://github.com/charmbracelet/gum) CLI binary
- **Styling:** Gum's built-in flags and a small helper library for consistent colors. We do NOT use Lipgloss or Bubbles directly since those require a Go binary. Gum's defaults + custom `--foreground` / `--border` flags are sufficient.
- **Distribution:** A single installable script or `curl | bash` installation. No npm, no Go build step.

**Why bash + Gum over a Go binary:**
- Zero compile step for users
- Easy to inspect and modify
- Gum provides 90% of the needed TUI primitives (spin, choose, confirm, input, style)
- The existing `dotfiles/scripts/lib/gum.sh` already proves this pattern works

---

## 3. Generated Repository Structure

`dotfriend start` generates a `~/dotfiles/` (or user-named) repo with the following structure. **Note:** `config/` and agent directories are populated dynamically based on what was detected on the user's machine, not a hardcoded list.

```
dotfiles/
├── Brewfile                          # taps, brews, casks, mas, go
├── install.sh                        # Full restore script (phased, dry-run, sudo keepalive)
├── bootstrap.sh                      # First-run script for brand-new Macs
├── scripts/
│   ├── validate.sh                   # Post-install validation (--fix, --json)
│   ├── backup.sh                     # Reverse-sync: copy machine state back to repo
│   └── lib/
│       ├── common.sh                 # Colors, logging, JSON helpers
│       ├── gum.sh                    # Gum wrappers with plain-bash fallbacks
│       ├── brew.sh                   # Brew validation helpers
│       ├── symlinks.sh               # Symlink validation & repair
│       ├── shell.sh                  # Shell config validation
│       ├── git-ssh.sh                # Git/SSH/GPG validation
│       ├── backup-config.sh          # Config sync logic
│       ├── backup-brew.sh            # Brewfile sync & discovery
│       └── backup-scout.sh           # Untracked app/config discovery
├── zsh/                              # .zshrc, .zsh_plugins.txt
├── config/                           # App configs symlinked to ~/.config/ (DYNAMIC — only detected tools)
│   ├── <detected-app-1>/
│   ├── <detected-app-2>/
│   └── ...
├── vscode/                           # settings.json, extensions.txt
├── cursor/                           # settings.json, keybindings.json, extensions.txt
├── claude/                           # CLAUDE.md, settings.json, hooks/, rules/, plugins/
├── codex/                            # AGENTS.md, RTK.md
├── agents/
│   ├── skills/                       # Shared agent skills
│   └── agent-docs/                   # Shared agent documentation
├── dock/
│   └── dock-apps.txt                 # Dock app list for dockutil
├── .gitignore
└── locations.md                      # Auto-generated config location reference
```

---

## 4. CLI Commands

| Command | Description |
|---------|-------------|
| `dotfriend start` | Interactive first-run wizard. Scans the Mac, lets the user select what to back up, and generates the dotfiles repo. |
| `dotfriend sync` | Incremental sync. Compares current machine state against the tracked repo, copies changed files, updates Brewfile, and optionally commits. |
| `dotfriend --help` | Show usage. |
| `dotfriend --version` | Show version. |

---

## 5. Agentic Tools Reference List

Before implementation, run the following command to build an exhaustive reference list of agentic tools and their config locations:

```bash
npx skills add vercel-labs/agent-skills
```

Parse the output to extract:
- Tool name (e.g., `claude`, `codex`, `cursor`, `aider`, `continue`)
- Config directory paths (e.g., `~/.claude/`, `~/.codex/`, `~/.cursor/`)
- Important files within each directory (e.g., `CLAUDE.md`, `settings.json`, `hooks/`)

**Embed this reference list inside dotfriend** as a JSON file (e.g., `lib/agent-tools.json`) so the tool can scan for these directories without requiring the user to have `npx` installed. The list is used during discovery to know *where* to look and *what* to back up.

Example embedded structure:
```json
{
  "agentic_tools": [
    {
      "name": "Claude Code",
      "id": "claude",
      "config_dirs": ["~/.claude"],
      "important_files": ["CLAUDE.md", "settings.json", "statusline.sh", "statusline.conf"],
      "important_dirs": ["hooks", "rules", "plugins"],
      "canonical_dir": "~/.claude",
      "symlinks_to_skip": ["~/.claude/skills", "~/.claude/agent-docs"]
    },
    {
      "name": "OpenAI Codex",
      "id": "codex",
      "config_dirs": ["~/.codex"],
      "important_files": ["AGENTS.md", "RTK.md"],
      "canonical_dir": "~/.codex"
    }
  ]
}
```

---

## 6. `dotfriend start` — Step-by-Step Flow

### Step 0: Welcome & Parallel Discovery
- Show styled welcome banner using `gum style`
- Prompt user to "Proceed" with `gum confirm`
- **Run discovery in parallel** (background jobs), each showing a `gum spin`:
  1. **Apps scan:** List `/Applications/*.app` + `~/Applications/*.app`, cross-reference with `brew list --cask` and `mas list`
  2. **Brew inventory:** `brew list --formula`, `brew list --cask`, `brew tap`
  3. **npm globals scan:** `npm list -g --depth=0` (if npm installed)
  4. **Agentic tools scan:** Using the embedded reference list, scan for config directories (`~/.claude/`, `~/.codex/`, `.agents/`, `.cursor/`, `.aider/`, etc.)
  5. **Dotfiles scan:** Find known dotfiles in `~` (`.zshrc`, `.bashrc`, `.gitconfig`, `.tmux.conf`, `.npmrc`, `.ignore`, etc.)
  6. **Config scan:** List directories in `~/.config/`
  7. **Editor scan:** Detect VS Code and Cursor settings + extension lists
  8. **Dock scan:** Current Dock layout via `dockutil --list` (if available)
- **Cache results** in `~/.cache/dotfriend/discovery.json` for fast re-runs

#### Discovery Performance Optimizations
- **Cask name cache:** Maintain a local JSON cache at `~/.cache/dotfriend/cask-map.json` mapping common app bundle names → cask names. Ship a seed list.
- **Batch brew descriptions:** Use `brew desc --cask` with multiple names at once, not one-by-one.
- **mas list once:** Run `mas list` a single time and do in-memory matching by app name / bundle ID.
- **Parallel jobs:** All 8 discovery tasks run concurrently. Results are collected before moving to Step 1.

---

### Step 1: macOS Apps
- Use `gum choose --no-limit` with all discovered apps pre-selected
- Display format: `App Name (cask: some-cask)` or `App Name (mas: app-name, id: 123)` or `App Name (manual)` or `App Name (unable to backup)`
- Allow user to deselect apps they don't want tracked
- For "unable to backup" apps, offer a `gum input` to manually enter a cask name
- Click "Confirm" → save selection, move to Step 2

---

### Step 2: Agentic Tools
- **Present detected agentic tools** from the discovery scan using the embedded reference list
- Use `gum choose --no-limit` with all detected tools pre-selected
- For each tool, show what will be backed up (e.g., `Claude Code: CLAUDE.md, settings.json, hooks/, rules/`)
- **User selects which tools to back up first**
- Only configs for **selected tools** are backed up — not all detected tools
- **Important:** Only back up canonical paths. Detect and skip symlinks (e.g., `.claude/skills/<name>` → `~/.agents/skills/<name>`)
- Confirm → move to Step 3

---

### Step 3: Brew Formulae
- Discover installed formulae via `brew leaves` (or `brew list --formula` as fallback)
- Use `gum choose --no-limit` with all formulae pre-selected
- Display format: `formula-name — description` (enriched via `brew desc` batch call)
- User can deselect formulae they don't want in the Brewfile
- Confirm → move to Step 4

---

### Step 4: Homebrew Taps
- **New step.** Discover installed taps via `brew tap`
- Use `gum choose --no-limit` with all taps pre-selected
- Display format: `tap-name` (e.g., `homebrew/cask`, `jordond/tap`, `tw93/tap`)
- User can deselect taps they don't want tracked
- Confirm → move to Step 5

---

### Step 5: npm Global Packages
- Discover globally installed npm packages via `npm list -g --depth=0`
- Detect special tooling: Bun (check `which bun`), `openlogs`, `agent-browser`, `@openai/codex`, `@googleworkspace/cli`
- Use `gum choose --no-limit` with detected packages pre-selected
- Display format: `package-name@version`
- User can deselect packages they don't want tracked
- **Note:** AI coding tools like Codex and OpenLogs are covered here if installed via npm. Claude Code is not an npm package and is handled separately in `install.sh` if the user has it installed.
- Confirm → move to Step 6

---

### Step 6: Dotfiles
- Use `gum choose --no-limit` with all discovered dotfiles pre-selected
- Explicitly scan for: `.zshrc`, `.bashrc`, `.gitconfig`, `.tmux.conf`, `.npmrc`, `.ignore`
- **Skip:** `.bash_profile`, shell history files (v2)
- Group by category: Shell, Git, Tools, Misc
- **Security note:** Never back up SSH private keys. Only `~/.ssh/config` is offered.
- User can deselect items they don't want to track
- Confirm → move to Step 7

---

### Step 7: Editors (VS Code & Cursor)
- Ask user: "Do you want to back up VS Code / Cursor settings and extensions?"
- If yes, for each editor:
  - Back up `settings.json`
  - Back up `keybindings.json` (if present)
  - Generate `extensions.txt` by running `code --list-extensions` or `cursor --list-extensions`
- Use `gum choose --no-limit` with both editors pre-selected if detected
- Confirm → move to Step 8

---

### Step 8: Dock & Default Apps
- Ask user:
  1. "Back up current Dock layout?" → If yes, export `dock/dock-apps.txt` using `dockutil --list` (or warn if `dockutil` not installed)
  2. "Set default app associations on restore?" → If yes, record `duti` rules for:
     - Default browser (Choosy)
     - Default media player (IINA)
- **If default apps are selected, ensure `duti` is added to the Brewfile** as a dependency
- These are written into `install.sh` as conditional setup functions
- Confirm → move to Step 9

---

### Step 9: Xcode Command Line Tools
- Show a TUI prompt:
  - Title: "Xcode Command Line Tools"
  - Description: "These tools are required for Homebrew, Git, and many developer tools. Recommended for all users."
  - Options: `[Confirm (Recommended)]` or `[Skip]`
- If confirmed, `install.sh` will include `xcode-select --install` and license acceptance logic
- If skipped, `install.sh` will emit a warning that some steps may fail
- Confirm / Skip → move to Step 10

---

### Step 10: Telemetry & Analytics
- Show a TUI prompt:
  - Title: "Disable Telemetry & Analytics"
  - Description: "Disable data collection for Homebrew, Go, GitHub CLI, Bun, npm, pnpm, and Deno. Recommended for privacy."
  - Options: `[Confirm (Recommended)]` or `[Skip]`
- If confirmed, `install.sh` will include:
  - `brew analytics off`
  - `go telemetry off`
  - `gh telemetry off` (if supported)
  - Bun `telemetry = false` in `~/.bunfig.toml`
  - `npm config set update-notifier false`
  - `pnpm config set update-notifier false`
- Confirm / Skip → move to Step 11

---

### Step 11: Generate Repository
- Create the dotfiles directory structure
- Write `Brewfile`:
  - Sections: `tap`, `brew`, `cask`, `mas`, `go`
  - Alphabetical within each section
  - Include only user-selected apps, formulae, and taps
  - Include `duti` if default app associations were selected
- Write `install.sh` with full feature parity:
  - Phased execution: Prerequisites → Configuration → App Setup → Final Setup → Validation
  - `--dry-run` support (preview all changes)
  - `sudo` keepalive session at start
  - Per-item progress during Brewfile install
  - **Soft-fail everywhere:** one bad package, npm install, dockutil command, or duti command does not stop the restore. All errors are logged and summarized at the end.
  - Symlink creation with backup of replaced files to `~/.dotfiles-backup/`
  - Copy (not symlink) for app-managed files (Karabiner, Choosy)
  - `rsync --delete` for agent skills/rules directories
  - Parallel background jobs for VS Code, Cursor, and AI tools setup
  - Dock restore, default app associations, telemetry disabling
  - Xcode CLI tools installation (if selected)
  - Homebrew prefix detection (`/opt/homebrew` on Apple Silicon, `/usr/local` on Intel)
  - Post-install validation via `scripts/validate.sh`
  - Environment toggles for customization:
    ```bash
    INSTALL_MAS=true        # Include Mac App Store apps
    BREW_UPGRADE=true       # Run brew upgrade before restore
    INSTALL_VALIDATE=false  # Skip post-install validation
    DOTFILES_DIR=/path      # Non-default dotfiles location
    BACKUP_ROOT=/path       # Where replaced files are backed up
    ```
  - coreutils `sha256sum` symlink: if `gsha256sum` is installed via coreutils, symlink `sha256sum` → `gsha256sum`
  - npm global installs: if Codex/OpenLogs were selected but npm is not available, install Node from the Brewfile first. Only install Bun if the user explicitly selected it in the npm globals step.
- Write `bootstrap.sh`:
  - Install Homebrew if missing
  - Persist Homebrew shellenv in `~/.zprofile`
  - Detect Homebrew prefix (`/opt/homebrew` vs `/usr/local`)
  - Install `git`, `gh`, and a minimal base set of casks
  - Clone the dotfiles repo
  - Optionally hand off to `install.sh` via `RUN_DOTFILES_INSTALL=true`
- Write `scripts/validate.sh` with `--json`, `--fix`, and targeted check modes
- Write `scripts/backup.sh` for reverse-sync maintenance
- Write `locations.md` auto-generated from the config map
- Initialize git repo with a sensible `.gitignore`:
  ```
  # Secrets and keys
  secrets/
  secrets/*.key
  secrets/*.pem
  secrets/*.p12
  ~/.config/sops/
  ~/.ssh/id_*
  ~/.ssh/*_rsa
  ~/.ssh/*_ed25519
  *.env
  .env.*

  # Caches
  *.cache
  .cache/
  **/__pycache__/
  *.pyc
  .pytest_cache/
  node_modules/

  # OS
  .DS_Store
  .AppleDouble
  .LSOverride
  Thumbs.db

  # Editor
  .vscode/
  .idea/
  *.swp
  *.swo
  *~

  # Logs
  *.log
  logs/

  # Temporary files
  tmp/
  temp/
  *.tmp
  *.bak
  *.backup

  # Build artifacts
  dist/
  build/
  .next/
  ```
- Show `gum spin` while generating files

---

### Step 12: GitHub Backup
- Check if `gh` CLI is installed. If not, offer to install it via Homebrew.
- Check `gh auth status`. If not authenticated, run `gh auth login`.
- Ask for repo name using `gum input` (default: `dotfiles`)
- Create a **private** repository on GitHub
- Commit all generated files
- Push to `origin` (detect default branch: `main` or `master`)
- Show success message with the repo URL

---

## 7. `dotfriend sync` — Incremental Sync

This is the ongoing maintenance command after the initial `start`.

### What it does:
1. **Re-run discovery** (using cached state where possible) to detect changes
2. **Config sync:** Compare tracked configs on disk to the repo. Copy changed files.
3. **Brew sync:** Detect new formulae, casks, taps, and MAS apps. Offer to add to `Brewfile`.
4. **npm sync:** Detect new global npm packages. Offer to add to a tracked list.
5. **Agent sync:** Sync selected agentic tools' configs (only those chosen during `start`)
6. **Show diff summary:** Use `git diff --stat` to show what changed
7. **Optional commit:** Prompt to commit and push with an auto-generated message

### Flags:
- `dotfriend sync --dry-run` — Preview changes without applying
- `dotfriend sync --no-commit` — Apply changes but don't commit
- `dotfriend sync --quick` — Non-interactive: sync configs only, skip discovery drill-down

---

## 8. Cask Name Discovery (Performance)

To avoid slow per-app `brew search` calls:

1. **Seed cache:** Ship `dotfriend` with a JSON file mapping common app bundle names to cask names (e.g., `Eagle.app` → `ogdesign-eagle`).
2. **Local cache:** Write hits to `~/.cache/dotfriend/cask-map.json` so future runs are instant.
3. **Batch fallback:** For apps not in cache, run `brew search --cask` in small batches or use a single `brew desc --cask` call on suspected matches.
4. **Manual override:** Always allow the user to type a cask name manually if the tool can't find one.

---

## 9. State Cache (`~/.cache/dotfriend/`)

All cached data lives in `~/.cache/dotfriend/`:

| File | Purpose |
|------|---------|
| `discovery.json` | Last discovery results (apps, dotfiles, configs, agents, brews, npm) |
| `cask-map.json` | App name → cask name mappings |
| `mas-map.json` | App name/bundle ID → MAS ID mappings |
| `last-sync.json` | Timestamps and checksums from last `sync` |

Cache is invalidated if the user selects "Rescan" or if file modification times have changed.

---

## 10. Testing Strategy

| Test | Approach |
|------|----------|
| **Unit tests** | Bash test framework ([bats](https://github.com/bats-core/bats-core)) for utility functions: cask name normalization, Brewfile parsing, config diffing |
| **Dry-run validation** | Every destructive step must support `--dry-run`. Run `dotfriend start --dry-run` and assert no files are created. |
| **Generated script linting** | Run `shellcheck` on generated `install.sh` and `bootstrap.sh` |
| **Idempotency test** | Run generated `install.sh` twice. Assert no changes on second run. |
| **E2E on clean macOS** | Use a VM (UTM / Tart) with fresh macOS. Run `bootstrap.sh` → `install.sh` → `validate.sh --fix` → verify symlinks and installed packages. |
| **Gum fallback test** | Uninstall Gum and verify the script still works with plain bash prompts |
| **Snapshot testing** | For known input sets, snapshot the generated `Brewfile` and `install.sh` to detect unintended changes |

---

## 11. v1 Scope — What's In / What's Out

### In v1
- [x] Full `dotfriend start` interactive wizard (12 steps)
- [x] `dotfriend sync` incremental maintenance
- [x] `bootstrap.sh` generation for first-run setup
- [x] `install.sh` with dry-run, sudo keepalive, soft-fail, backups
- [x] Brewfile generation (tap, brew, cask, mas, go)
- [x] macOS Apps discovery and selection
- [x] **Agentic tools discovery using exhaustive reference list** (`npx skills add vercel-labs/agent-skills`)
- [x] **User selects which agentic tools to back up, only selected tools' configs are backed up**
- [x] Brew formulae discovery and selection
- [x] **Homebrew taps discovery and selection**
- [x] npm global packages discovery and selection
- [x] Dotfiles and `~/.config` discovery and backup
- [x] VS Code / Cursor settings and extensions backup
- [x] Dock layout backup and restore
- [x] Default app associations (duti) in install.sh
- [x] Xcode CLI tools setup step
- [x] Telemetry & analytics disabling step
- [x] `scripts/validate.sh` with `--fix` and `--json`
- [x] `scripts/backup.sh` for reverse-sync
- [x] GitHub repo creation and push via `gh`
- [x] Parallel discovery and caching
- [x] Homebrew prefix detection (Apple Silicon / Intel)
- [x] Soft-fail for all setup functions (npm, dockutil, duti, brew)
- [x] Comprehensive `.gitignore` template

### Out of v1 (Future)
- [ ] macOS preferences export and restore (`.plist` domains, `.macos` defaults script)
- [ ] Secrets management (`sops` / `age`) — complex key distribution
- [ ] Mackup integration — requires iCloud and user education
- [ ] Auto-commit daemon / continuous background sync
- [ ] Cross-platform support (Linux)
- [ ] GUI app state backup (databases, containers)
- [ ] Full MAS automation (still requires App Store sign-in)
- [ ] Shell tool cache refresh (zoxide, direnv, fzf, atuin)
- [ ] Go tools scan (`go install` binaries)
- [ ] `.bash_profile` and shell history backup
- [ ] AI coding tools as a separate step (covered by npm/brew discovery)

---

## 12. Open Questions Before Implementation

1. **Distribution:** Do we want a one-liner installer (`curl -fsSL ... | bash`) or just a git clone + symlink?
2. **Gum dependency:** Do we bundle a Gum install check in `dotfriend` itself, or assume it's installed?
3. **Seed cask list:** How comprehensive should the built-in app→cask mapping be? Top 200 apps?
4. **Repo name default:** `dotfiles` is standard. Do we allow creating the repo in a non-default location?
5. **Existing repo handling:** If `~/dotfiles` already exists, do we merge, overwrite, or abort?
6. **npm without Bun/Node:** If the user selects Codex/OpenLogs but doesn't have Bun or Node, should `install.sh` install Node from the Brewfile first?

---

## 13. Success Criteria

A user should be able to:
1. Install `dotfriend` with one command
2. Run `dotfriend start` and complete the wizard in under 5 minutes
3. Push a private `dotfiles` repo to GitHub
4. On a brand-new Mac, run `bootstrap.sh` and have a fully configured machine
5. Run `dotfriend sync` weekly to keep the repo in sync with their machine
