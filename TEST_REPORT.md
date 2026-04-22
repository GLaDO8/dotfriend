# dotfriend Test Report

Generated from parallel agent testing across 4 test scenarios.

---

## Critical Bugs (Must Fix Before Release)

### 1. `validate.sh` is completely non-functional
**Location:** `templates/scripts/validate.sh`
**Severity:** CRITICAL

- **Top-level `local` declarations** (lines ~406, 407, etc.): `local` outside a function causes `local: can only be used in a function` under `set -e`, killing the script immediately.
- **`((total_*++))` with `set -e`**: Bash arithmetic `((0++))` returns exit code 1. The script hits the first counter increment and dies silently. **Zero output, zero checks run.**
- **Fix:** Change `local first=true` → `first=true`, and change all `((total_pass++))` to `((total_pass++)) || true`.

### 2. `dotfriend` entry script crashes on `start`
**Location:** `dotfriend` line ~106
**Severity:** CRITICAL

- `local dry_run=false` inside the top-level `case` block. `local` is only valid inside functions.
- **Error:** `./dotfriend: line 106: local: can only be used in a function`
- **Fix:** Remove `local` keyword: `dry_run=false`

### 3. Agent sync is completely broken
**Location:** `lib/sync.sh` line ~458
**Severity:** CRITICAL

- `jq -r '.agents // empty | .[]'` pretty-prints JSON objects across multiple lines. The `while read` loop then reads each line as a separate agent ID, producing nonsense paths like `/var/folders/.../.{` and `/var/folders/.../.  "id": "claude",`.
- Also hardcodes `~/.${agent}` instead of looking up `canonical_dir` from `agent-tools.json`.
- **Fix:** Use `jq -r '.agents // empty | .[] | .id'` and look up `canonical_dir` from `agent-tools.json`.

### 4. `gum_spin` fallback crashes discovery
**Location:** `lib/gum.sh`
**Severity:** CRITICAL

- When gum is missing, the fallback strips `--spinner`, `--title`, `--show-output` flags but **leaves their arguments** in the command array.
- **Error:** `dot: command not found` printed 11 times (once per discovery task).
- **Fix:** Consume flag arguments: `--spinner|--title|--show-output) shift 2 ;;`

### 5. `discovery.sh` EXIT trap crashes on exit
**Location:** `lib/discovery.sh` line ~295
**Severity:** CRITICAL

- `trap 'rm -rf "$tmpdir"' EXIT` is set inside `run_discovery` where `tmpdir` is `local`. When the function returns, `tmpdir` is destroyed. The EXIT trap fires with `set -u` active and fails because `$tmpdir` is unbound.
- **Error:** `tmpdir: unbound variable`
- **Fix:** Either use `trap "rm -rf '$tmpdir'" EXIT` (expand at trap-set time) or call `trap - EXIT` before returning + manually `rm -rf "$tmpdir"`.

---

## High Priority Bugs

### 6. Empty array expansion produces invalid JSON
**Location:** `lib/wizard.sh` (multiple locations)
**Severity:** HIGH

- `${array[@]:-}` expands to a single `""` entry when the array is empty, causing JSON like `"taps": [""]`.
- **Fix:** Remove `:-` from all array expansions in `_write_selections_json`: `"${SELECTED_TAPS[@]}"` instead of `"${SELECTED_TAPS[@]:-}"`.

### 7. `gum_confirm` wrapper passes wrong flag to gum
**Location:** `lib/gum.sh`
**Severity:** HIGH

- `gum confirm --prompt "..."` is invalid. Gum's flag is not `--prompt`, it's a positional argument.
- **Error:** `gum: error: unknown flag --prompt, did you mean one of "--prompt.foreground"...?`
- **Fix:** Translate `--prompt` into a positional argument before passing to `gum confirm`.

### 8. npm sync text parsing is broken
**Location:** `lib/sync.sh`
**Severity:** HIGH

- Treats `npm prefix -g` path as a package name.
- Scoped packages (`@biomejs/biome@2.4.12`) are mangled by `sed 's/@.*//'`.
- **Fix:** Use `npm list -g --depth=0 --json` (consistent with `discover_npm_globals`) instead of fragile text parsing.

### 9. Sync fails silently when repo not found
**Location:** `lib/sync.sh` line ~608
**Severity:** HIGH

- `REPO_DIR="$(_find_repo)"` with `set -e` active: when `_find_repo` returns 1, bash exits immediately before the `if [[ -z "$REPO_DIR" ]]` check.
- **Fix:** `REPO_DIR="$(_find_repo)" || true`

### 10. `cask-map.json` has 29 duplicate keys
**Location:** `lib/cask-map.json`
**Severity:** HIGH

- Standard JSON parsers silently overwrite earlier values, causing inconsistent behavior.
- **Fix:** Deduplicate the file (e.g., via Python script or manual cleanup).

---

## Medium Priority Issues

### 11. Generated scripts have unguarded destructive operations
**Location:** `templates/install.sh`, `templates/bootstrap.sh`
**Severity:** MEDIUM

- `_symlink()`: `rm -rf "$dest"` and `ln -s` are unguarded. Permission failures cause hard exits.
- `_copy()`: `cp -a` is unguarded.
- `_rsync_agent()`: `rsync` is unguarded.
- `bootstrap.sh`: `brew install`, `git clone` are unguarded under `set -e`.
- **Fix:** Wrap in `soft_run` or `|| { log_error ...; }`.

### 12. `prompt_input` and `gum_choose` fallbacks pollute stdout
**Location:** `lib/common.sh`, `lib/gum.sh`
**Severity:** MEDIUM

- Fallback prompts print to stdout, corrupting captured values when output is piped.
- **Fix:** Redirect prompt/menu output to `&2`.

### 13. `printf` escaping issues in `generate.sh`
**Location:** `lib/generate.sh`
**Severity:** MEDIUM

- Variable-containing format strings in `printf` cause unexpected expansion when generating bash code.
- **Fix:** Use single-quoted format strings and pass variables as arguments.

### 14. Template placeholders confuse `shellcheck`
**Location:** `templates/install.sh`, `templates/bootstrap.sh`
**Severity:** LOW

- `{{XCODE_BLOCK}}`, `{{BASE_CASKS_BLOCK}}` trigger parse errors in shellcheck.
- **Note:** This is expected for templates; run shellcheck on the *rendered* output instead.

### 15. `backup.sh` has `rm -rf` with potentially empty vars
**Location:** `templates/scripts/backup.sh`
**Severity:** MEDIUM

- `rm -rf "${config_dir}/${name}"` — if `config_dir` is empty, this becomes `rm -rf "/name"` (root deletion risk).
- **Fix:** Use `${config_dir:?}/${name}` to fail safe.

---

## Passed Tests

| Test | Status |
|------|--------|
| `--help`, `-h`, `--version`, `-v` | ✅ PASS (after fixes) |
| Unknown command handling | ✅ PASS |
| `install.sh --dry-run` | ✅ PASS |
| No hardcoded paths in templates | ✅ PASS |
| `agent-tools.json` structure | ✅ PASS |
| Discovery functions with missing tools | ✅ PASS (graceful empty returns) |
| `bootstrap.sh` structure & URLs | ✅ PASS |
| `install.sh` dry-run does not modify files | ✅ PASS |

---

## Files Requiring Fixes

1. `dotfriend` — remove `local` from top-level case block
2. `lib/gum.sh` — fix `gum_confirm` flag, `gum_spin` fallback, `gum_choose` stdout pollution
3. `lib/common.sh` — redirect `prompt_input` to stderr
4. `lib/discovery.sh` — fix EXIT trap with local `tmpdir`
5. `lib/wizard.sh` — fix empty array `:-` expansion
6. `lib/generate.sh` — fix `printf` escaping, BACKUP_ROOT sed pattern
7. `lib/sync.sh` — fix agent sync JSON parsing, npm text parsing, `_find_repo` `set -e` issue
8. `templates/scripts/validate.sh` — fix top-level `local`, `(( ))` arithmetic, SC2015/SC2295/SC2088
9. `templates/scripts/backup.sh` — fix `rm -rf` empty var risk, SC2129
10. `templates/install.sh` — add guards to `_symlink`, `_copy`, `_rsync_agent`, `eval brew shellenv`
11. `templates/bootstrap.sh` — add guards to `brew install`, `git clone`
12. `lib/cask-map.json` — deduplicate 29 duplicate keys

---

## Recommended Fix Order

1. **Critical first:** `validate.sh`, `dotfriend` entry script, `gum_spin`, `discovery.sh` trap, `sync.sh` agent sync
2. **High next:** `gum_confirm`, `wizard.sh` arrays, `sync.sh` npm parsing, `sync.sh` repo finding, `cask-map.json`
3. **Medium last:** Guards in generated templates, stdout pollution, `generate.sh` printf escaping, `backup.sh` safety
