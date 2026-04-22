# dotfriend

A bash-based CLI that uses [Gum](https://github.com/charmbracelet/gum) to interactively scan a macOS system and generate a version-controlled `dotfiles` repository, complete with `Brewfile`, `install.sh`, `bootstrap.sh`, and config backups.

---

## Tech Stack

- **Language:** Bash (no compilation, no package manager for the tool itself)
- **TUI:** [Gum](https://github.com/charmbracelet/gum) CLI binary (**hard requirement** — the CLI auto-installs it via Homebrew if missing)
- **JSON:** `jq` preferred; naive `grep`/`sed` fallbacks for fresh Macs
- **Platform:** macOS only (Apple Silicon & Intel)

---

## Project Structure

```
dotfriend/
├── dotfriend              # Main entry point. Parses args, sources libs, runs wizard/sync.
├── lib/
│   ├── common.sh          # Colors, logging, JSON helpers, brew detection, prompt fallbacks
│   ├── gum.sh             # Gum wrappers (hard requirement; fallbacks kept for testing only).
│   ├── discovery.sh       # Scans apps, brew, npm, agentic tools, dotfiles, editors, dock.
│   ├── wizard.sh          # 12-step interactive wizard (dotfriend start). Calls discovery.
│   ├── generate.sh        # Creates the dotfiles repo from wizard selections.
│   ├── sync.sh            # Incremental sync (dotfriend sync). Config, brew, npm, agent sync.
│   ├── agent-tools.json   # Reference list of agentic tools and their config paths.
│   └── cask-map.json      # App bundle name → Homebrew cask mappings.
├── templates/
│   ├── bootstrap.sh       # First-run script for brand-new Macs (installs brew, git, gh, gum).
│   ├── install.sh         # Full restore script. Phased, dry-run, sudo keepalive, soft-fail.
│   └── scripts/
│       ├── validate.sh    # Post-install validation (--fix, --json).
│       └── backup.sh      # Reverse-sync: copy machine state back to repo.
├── tests/
│   ├── harness.sh         # Test harness.
│   └── verify_fixes.sh    # Regression tests for known bugs.
├── PLAN.md                # Full product spec and v1 scope.
└── TEST_REPORT.md         # Bug tracker with severity, location, and fix instructions.
```

---

## How the CLI Works

### Entry Point (`dotfriend`)

1. **Sources** `lib/common.sh` and `lib/gum.sh`.
2. **Requires Gum:** Calls `require_gum()` — auto-installs via Homebrew if missing, otherwise exits with instructions.
3. **Dependency check:** Scans for `git`, `brew`, `jq`, `gh`, `npm`, `mas`, and Xcode CLI tools. Warns but does not block on optional deps.
4. **Dispatches** to:
   - `dotfriend start` → sources `lib/wizard.sh` → runs `wizard_start()` → sources `lib/generate.sh` → runs `generate_repo()`.
   - `dotfriend sync` → sources `lib/sync.sh` → runs `cmd_sync()`.

### Wizard Flow (`lib/wizard.sh`)

12 sequential steps. Each step:
1. Reads from `~/.cache/dotfriend/discovery.json` (produced by `run_discovery()` in `lib/discovery.sh`).
2. Presents options via `gum_choose --no-limit`.
3. Stores selections in global arrays (`SELECTED_APPS`, `SELECTED_FORMULAE`, etc.).
4. At the end, writes everything to `~/.cache/dotfriend/selections.json` via `_write_selections_json()`.

### Discovery (`lib/discovery.sh`)

- Runs 11 parallel subshells inside a single `gum_spin`.
- Each task writes to a temp file. Results are assembled into `discovery.json`.
- Gracefully returns empty if tools (brew, mas, npm) are missing.

### Generation (`lib/generate.sh`)

- Reads `selections.json`.
- Generates `Brewfile`, `install.sh`, `bootstrap.sh`, `.gitignore`, `locations.md`.
- Copies configs, editor settings, agent configs, dock layout into the repo.
- Initializes git and optionally pushes to GitHub via `gh`.

### Sync (`lib/sync.sh`)

- `sync_configs`: Compares tracked `config/` dirs to live `~/.config/` dirs.
- `sync_brewfile`: Detects new taps/formulae/casks/mas apps and appends to `Brewfile`.
- `sync_npm`: Detects new global npm packages and appends to `npm-globals.txt`.
- `sync_agents`: Copies changed files for selected agentic tools.

---

## Critical Conventions for Agents

### Bash Safety
- **Every script** uses `set -euo pipefail`.
- **`local` is only valid inside functions.** Never use `local` at the top level of a script or inside a `case` block.
- **`((var++))` returns exit code 1 when `var` is 0.** Under `set -e`, this kills the script. Always use `((var++)) || true`.

### Gum Integration
- **Gum is a hard requirement.** The entry script (`dotfriend`) calls `require_gum()` before anything else. If Gum is missing and Homebrew is present, it auto-installs. If Homebrew is missing, it exits with install instructions.
- Never call `gum` directly; use the wrappers in `lib/gum.sh` (`gum_choose`, `gum_confirm`, `gum_input`, `gum_spin`, `gum_style`).
- The wrappers still contain plain-bash fallbacks for testing (e.g. setting `GUM_AVAILABLE=false`), but the production path always has Gum available.
- `gum confirm` does **not** accept `--prompt`. The wrapper translates it to a positional argument.
- `gum choose --no-limit` calls must include `--no-show-help` to hide the outdated "x for toggle" footer.
- Theme env vars are set in `gum.sh`:
  - `GUM_CHOOSE_CURSOR_FOREGROUND=""` (white cursor)
  - `GUM_CHOOSE_SHOW_HELP="false"` (suppress footer)

### JSON Handling
- Always check `command -v jq` first. Use `jq` when available.
- Fall back to naive `grep`/`sed` only for simple string values. Never rely on fallbacks for nested JSON arrays.
- When parsing arrays with `jq -r '.items[] | .id'`, ensure the query extracts scalars, not objects, to avoid multi-line garbage in `while read` loops.

### Discovery & Caching
- Discovery writes to `~/.cache/dotfriend/discovery.json`.
- Selections write to `~/.cache/dotfriend/selections.json`.
- All discovery functions gracefully return empty if the underlying tool is missing (e.g., `mas`, `npm`, `brew`).

### Error Handling
- **Soft-fail everywhere in generated scripts.** One bad brew formula, npm package, or dockutil command must not stop the restore. Use `soft_run` or `|| true`.
- `trap` with `set -u` is dangerous. If a `trap` references a `local` variable, expand the variable at trap-set time: `trap "rm -rf '$tmpdir'" EXIT`, and always call `trap - EXIT` before returning from the function.

### Path Safety
- Never use `rm -rf "${var}/path"` unless `var` is validated non-empty. Use `${var:?}` to fail safe.
- `brew_prefix()` checks `/opt/homebrew` (Apple Silicon) → `/usr/local` (Intel) → `$HOME/homebrew`.

---

## Repeated Mistakes & Solutions

| Mistake | Why It Happens | Solution |
|---------|---------------|----------|
| `local: can only be used in a function` | Using `local` at top level or in `case` blocks. | Remove `local` keyword. |
| `((0++))` kills script under `set -e` | Arithmetic `(( ))` returns 1 when the expression evaluates to 0. | Append `\|\| true`: `((count++)) \|\| true` |
| `tmpdir: unbound variable` on exit | `trap` references a `local` variable that was destroyed on function return. | Expand in trap string: `trap "rm -rf '$tmpdir'" EXIT`; clear before return: `trap - EXIT` |
| `gum confirm --prompt` fails | Gum's `confirm` takes the prompt as a positional arg, not `--prompt`. | The wrapper in `gum.sh` already handles this. Do not pass `--prompt` directly to `gum`. |
| `gum_spin` fallback crashes | Fallback strips flags but leaves their arguments in the command array. | Ensure the fallback consumes both the flag and its argument: `shift 2` for `--spinner`, `--title`, `--show-output`. |
| Empty array expansion → `[""]` in JSON | `"${array[@]:-}"` expands to a single empty string when the array is empty. | Use `"${array[@]}"` without `:-` in `_write_selections_json`. |
| Agent sync reads JSON objects as IDs | `jq -r '.agents[]'` pretty-prints objects across multiple lines. | Use `jq -r '.agents[] \| .id'` to extract scalar IDs only. |
| Sync exits silently when repo not found | `_find_repo` returns 1; `set -e` kills the script before the `if [[ -z ]]` check. | Use `REPO_DIR="$(_find_repo)" \|\| true` |
| `printf` with variable format strings | `printf "$var\n"` expands `$var` as the format string, causing crashes if `%` is present. | Use `printf '%s\n' "$var"` |
| `cask-map.json` has duplicate keys | JSON parsers silently overwrite duplicates, causing inconsistent behavior. | Deduplicate before adding entries. |
| Generated scripts unguarded under `set -e` | `_symlink`, `_copy`, `_rsync_agent` call `rm -rf` or `cp` without `||` guards. | Wrap destructive calls in `soft_run` or `\|\| { log_error ...; }` |
| Prompt fallbacks pollute stdout | `prompt_input` and `gum_choose` fallbacks print menus to stdout, corrupting captured output. | Redirect prompts and menus to `>&2`. |

---

## Testing

- Run `./tests/verify_fixes.sh` after any change to `lib/` or `templates/`.
- Run `shellcheck` on rendered output (not templates with `{{PLACEHOLDERS}}`).
- Test the gum-fallback path by setting `GUM_AVAILABLE=false` before sourcing `gum.sh`.

---

## Quick Reference: Files to Edit for Common Tasks

| Task | File(s) |
|------|---------|
| Add a new wizard step | `lib/wizard.sh` |
| Change discovery logic | `lib/discovery.sh` |
| Change generated output | `lib/generate.sh` + `templates/` |
| Fix TUI styling | `lib/gum.sh` |
| Add a new agentic tool | `lib/agent-tools.json` + `lib/discovery.sh` |
| Fix sync behavior | `lib/sync.sh` |
| Fix install/restore logic | `templates/install.sh` or `templates/bootstrap.sh` |
| Update CLI args / commands | `dotfriend` (entry script) |
