#!/usr/bin/env bash
# dotfriend — Discovery engine
# shellcheck shell=bash
#
# Scans the local environment (apps, brew packages, dotfiles, editors, etc.)
# and caches the results in ~/.cache/dotfriend/discovery.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=gum.sh
source "${SCRIPT_DIR}/gum.sh"

# ─────────────────────────────────────────────────────────────
# App discovery
# ─────────────────────────────────────────────────────────────

# Scan /Applications and ~/Applications, cross-referencing with Homebrew
# casks and Mac App Store (mas) entries.
# Output format: App Name|cask:<token>  or  App Name|mas:<name>,id:<id>  or  App Name|manual
discover_apps() {
  local -a apps=()
  local app app_name

  for app in /Applications/*.app "${HOME}"/Applications/*.app; do
    # Skip literal globs when directory is empty
    [[ -e "$app" ]] || continue
    [[ "$app" == "/Applications/*.app" ]] && continue
    [[ "$app" == "${HOME}/Applications/*.app" ]] && continue
    app_name="$(basename "$app" .app)"
    apps+=("$app_name")
  done

  if [[ ${#apps[@]} -eq 0 ]]; then
    return 0
  fi

  local casks=""
  local mas_apps=""
  local cask_map_file="${SCRIPT_DIR}/cask-map.json"
  local cask_map=""

  if has_brew; then
    casks="$(brew list --cask 2>/dev/null || true)"
  fi

  if command -v mas >/dev/null 2>&1; then
    mas_apps="$(mas list 2>/dev/null || true)"
  fi

  # Load cask-map.json if available
  if [[ -f "$cask_map_file" ]] && command -v jq >/dev/null 2>&1; then
    cask_map="$(cat "$cask_map_file")"
  fi

  local cask_name mas_line mas_id mapped_cask

  for app_name in "${apps[@]}"; do
    # Heuristic: lowercase with hyphens matches most cask tokens
    cask_name="$(printf '%s' "$app_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
    mapped_cask=""

    # Look up in cask-map.json first
    if [[ -n "$cask_map" ]]; then
      mapped_cask="$(printf '%s' "$cask_map" | jq -r --arg key "$app_name.app" '.[$key] // empty' 2>/dev/null || true)"
    fi

    if [[ -n "$mas_apps" ]] && mas_line="$(printf '%s\n' "$mas_apps" | grep -iF "$app_name" | head -n1)"; then
      mas_id="$(printf '%s' "$mas_line" | awk '{print $1}')"
      # Use mapped cask name if available, otherwise heuristic
      if [[ -n "$mapped_cask" && "$mapped_cask" != "null" ]]; then
        printf '%s|mas:%s,id:%s\n' "$app_name" "$mapped_cask" "$mas_id"
      else
        printf '%s|mas:%s,id:%s\n' "$app_name" "$cask_name" "$mas_id"
      fi
    elif [[ -n "$mapped_cask" && "$mapped_cask" != "null" ]]; then
      # Found in cask-map.json — include even if not currently installed via brew
      printf '%s|cask:%s\n' "$app_name" "$mapped_cask"
    elif [[ -n "$casks" ]] && printf '%s\n' "$casks" | grep -qiFx "$cask_name"; then
      printf '%s|cask:%s\n' "$app_name" "$cask_name"
    elif [[ -n "$casks" ]] && printf '%s\n' "$casks" | grep -qiFx "$app_name"; then
      printf '%s|cask:%s\n' "$app_name" "$app_name"
    else
      printf '%s|manual\n' "$app_name"
    fi
  done | sort -u
}

# ─────────────────────────────────────────────────────────────
# Homebrew discovery
# ─────────────────────────────────────────────────────────────

# List installed formulae with descriptions.
# Output format: formula-name|description
discover_brew_formulae() {
  if ! has_brew; then
    return 0
  fi

  local formulae
  formulae="$(brew leaves 2>/dev/null || brew list --formula 2>/dev/null || true)"
  if [[ -z "$formulae" ]]; then
    return 0
  fi

  local output
  # shellcheck disable=SC2086
  output="$(brew desc $formulae 2>/dev/null | sed 's/: /|/' || true)"

  if [[ -n "$output" ]]; then
    printf '%s\n' "$output"
  else
    # Fallback: names only
    printf '%s\n' "$formulae" | sed 's/$/|/'
  fi
}

# List installed casks.
discover_brew_casks() {
  if ! has_brew; then
    return 0
  fi
  brew list --cask 2>/dev/null || true
}

# List tapped repositories.
discover_brew_taps() {
  if ! has_brew; then
    return 0
  fi
  brew tap 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────
# npm discovery
# ─────────────────────────────────────────────────────────────

# List globally installed npm packages.
# Output format: package@version
discover_npm_globals() {
  if ! command -v npm >/dev/null 2>&1; then
    return 0
  fi

  # Prefer JSON + Node for robust scoped-package support
  if command -v node >/dev/null 2>&1; then
    npm list -g --depth=0 --json 2>/dev/null | node -e '
      const data = require("fs").readFileSync(0, "utf8");
      const json = JSON.parse(data);
      const deps = json.dependencies || {};
      for (const [name, info] of Object.entries(deps)) {
        console.log(name + "@" + info.version);
      }
    ' 2>/dev/null || true
  else
    # Fallback text-tree parsing
    npm list -g --depth=0 2>/dev/null \
      | grep -oE '(\@[^/]+/)?[^@[:space:]]+@[^[:space:]]+' \
      || true
  fi
}

# ─────────────────────────────────────────────────────────────
# Agentic tools discovery
# ─────────────────────────────────────────────────────────────

# Read lib/agent-tools.json and check whether each tool's config directory
# exists under $HOME.
# Output format: tool-id|Tool Name|config_dir|status
discover_agentic_tools() {
  local tools_file="${SCRIPT_DIR}/agent-tools.json"
  if [[ ! -f "$tools_file" ]]; then
    return 0
  fi

  local parser="none"
  if command -v jq >/dev/null 2>&1; then
    parser="jq"
  elif command -v python3 >/dev/null 2>&1; then
    parser="python3"
  fi

  if [[ "$parser" == "none" ]]; then
    log_warn "Cannot parse agent-tools.json: install jq or python3"
    return 0
  fi

  local raw=""
  if [[ "$parser" == "jq" ]]; then
    raw="$(jq -r '.agentic_tools[] | "\(.id)|\(.name)|\(.canonical_dir)"' "$tools_file" 2>/dev/null || true)"
  else
    raw="$(python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
tools = data.get("agentic_tools", [])
for tool in tools:
    if not isinstance(tool, dict):
        continue
    print("{}|{}|{}".format(
        tool.get("id", ""),
        tool.get("name", ""),
        tool.get("canonical_dir", tool.get("config_dirs", [""])[0])
    ))
' "$tools_file" 2>/dev/null || true)"
  fi

  local tid name cfg status
  while IFS='|' read -r tid name cfg; do
    [[ -n "$tid" ]] || continue
    # Expand leading ~ to $HOME (canonical_dir values are like ~/.claude)
    cfg="${cfg/#\~/$HOME}"
    if [[ -d "$cfg" ]]; then
      status="found"
    else
      status="missing"
    fi
    printf '%s|%s|%s|%s\n' "$tid" "$name" "$cfg" "$status"
  done <<< "$raw"
}

# ─────────────────────────────────────────────────────────────
# Dotfile & config discovery
# ─────────────────────────────────────────────────────────────

# Scan home directory for known dotfiles.
# Skips .bash_profile and any shell history files.
discover_dotfiles() {
  local files=(
    .zshrc
    .bashrc
    .gitconfig
    .tmux.conf
    .npmrc
    .ignore
  )
  local f
  for f in "${files[@]}"; do
    if [[ -f "${HOME}/${f}" ]]; then
      printf '%s\n' "$f"
    fi
  done
}

# List directories inside ~/.config/.
discover_config_dirs() {
  local dir
  for dir in "${HOME}/.config"/*/; do
    [[ -d "$dir" ]] || continue
    basename "$dir"
  done | sort
}

# ─────────────────────────────────────────────────────────────
# Editor discovery
# ─────────────────────────────────────────────────────────────

# Discover VS Code settings and extensions.
# Multiline output: first line is settings path, remaining lines are extensions.
discover_vscode() {
  local settings_path="${HOME}/Library/Application Support/Code/User/settings.json"
  if [[ -f "$settings_path" ]]; then
    printf 'settings:%s\n' "$settings_path"
  else
    printf 'settings:missing\n'
  fi

  if command -v code >/dev/null 2>&1; then
    code --list-extensions 2>/dev/null || true
  fi
}

# Discover Cursor settings and extensions.
discover_cursor() {
  local settings_path="${HOME}/Library/Application Support/Cursor/User/settings.json"
  if [[ -f "$settings_path" ]]; then
    printf 'settings:%s\n' "$settings_path"
  else
    printf 'settings:missing\n'
  fi

  if command -v cursor >/dev/null 2>&1; then
    cursor --list-extensions 2>/dev/null || true
  fi
}

# ─────────────────────────────────────────────────────────────
# Dock discovery
# ─────────────────────────────────────────────────────────────

# List Dock items if dockutil is installed.
discover_dock() {
  if command -v dockutil >/dev/null 2>&1; then
    dockutil --list 2>/dev/null || true
  fi
}

# ─────────────────────────────────────────────────────────────
# Orchestration
# ─────────────────────────────────────────────────────────────

# Run all discovery tasks in parallel, cache results to discovery.json,
# and provide TUI feedback via gum_spin.
run_discovery() {
  ensure_dir "$DOTFRIEND_CACHE_DIR"
  local cache_file="${DOTFRIEND_CACHE_DIR}/discovery.json"

  # Absolute path to this script so subshells can source it regardless of cwd
  local script_path
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  local tmpdir
  tmpdir="$(mktemp -d)"
  # Clean up temp directory on exit (expand tmpdir now so the local var is not needed later)
  trap "rm -rf '$tmpdir'" EXIT

  local -a pids=()

  # Run all discovery tasks in parallel inside a SINGLE gum_spin subshell.
  # This avoids multiple concurrent gum processes querying terminal colors
  # and causing ANSI escape code garbage (OSC 11 responses) to leak.
  gum_spin --spinner dot --title "Scanning your system..." \
    -- bash -c "
      source '$script_path'
      exit_code=0
      discover_apps > '$tmpdir/apps.txt' 2>/dev/null &
      p1=\$!
      discover_brew_formulae > '$tmpdir/formulae.txt' 2>/dev/null &
      p2=\$!
      discover_brew_casks > '$tmpdir/casks.txt' 2>/dev/null &
      p3=\$!
      discover_brew_taps > '$tmpdir/taps.txt' 2>/dev/null &
      p4=\$!
      discover_npm_globals > '$tmpdir/npm_globals.txt' 2>/dev/null &
      p5=\$!
      discover_agentic_tools > '$tmpdir/agents.txt' 2>/dev/null &
      p6=\$!
      discover_dotfiles > '$tmpdir/dotfiles.txt' 2>/dev/null &
      p7=\$!
      discover_config_dirs > '$tmpdir/config_dirs.txt' 2>/dev/null &
      p8=\$!
      discover_vscode > '$tmpdir/vscode.txt' 2>/dev/null &
      p9=\$!
      discover_cursor > '$tmpdir/cursor.txt' 2>/dev/null &
      p10=\$!
      discover_dock > '$tmpdir/dock.txt' 2>/dev/null &
      p11=\$!
      if ! wait \$p1; then exit_code=1; fi
      if ! wait \$p2; then exit_code=1; fi
      if ! wait \$p3; then exit_code=1; fi
      if ! wait \$p4; then exit_code=1; fi
      if ! wait \$p5; then exit_code=1; fi
      if ! wait \$p6; then exit_code=1; fi
      if ! wait \$p7; then exit_code=1; fi
      if ! wait \$p8; then exit_code=1; fi
      if ! wait \$p9; then exit_code=1; fi
      if ! wait \$p10; then exit_code=1; fi
      if ! wait \$p11; then exit_code=1; fi
      exit \$exit_code
    "

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log_warn "Some discovery tasks finished with errors."
  fi

  # Assemble the cache file from individual temp outputs
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg apps "$(cat "$tmpdir/apps.txt" 2>/dev/null || true)" \
      --arg formulae "$(cat "$tmpdir/formulae.txt" 2>/dev/null || true)" \
      --arg casks "$(cat "$tmpdir/casks.txt" 2>/dev/null || true)" \
      --arg taps "$(cat "$tmpdir/taps.txt" 2>/dev/null || true)" \
      --arg npm_globals "$(cat "$tmpdir/npm_globals.txt" 2>/dev/null || true)" \
      --arg agents "$(cat "$tmpdir/agents.txt" 2>/dev/null || true)" \
      --arg dotfiles "$(cat "$tmpdir/dotfiles.txt" 2>/dev/null || true)" \
      --arg config_dirs "$(cat "$tmpdir/config_dirs.txt" 2>/dev/null || true)" \
      --arg vscode "$(cat "$tmpdir/vscode.txt" 2>/dev/null || true)" \
      --arg cursor "$(cat "$tmpdir/cursor.txt" 2>/dev/null || true)" \
      --arg dock "$(cat "$tmpdir/dock.txt" 2>/dev/null || true)" \
      '{
        apps: $apps,
        formulae: $formulae,
        casks: $casks,
        taps: $taps,
        npm_globals: $npm_globals,
        agents: $agents,
        dotfiles: $dotfiles,
        config_dirs: $config_dirs,
        vscode: $vscode,
        cursor: $cursor,
        dock: $dock
      }' > "$cache_file"
  else
    # Portable fallback without jq
    {
      printf '{\n'
      printf '  "apps": "%s",\n' "$(json_escape "$(cat "$tmpdir/apps.txt" 2>/dev/null || true)")"
      printf '  "formulae": "%s",\n' "$(json_escape "$(cat "$tmpdir/formulae.txt" 2>/dev/null || true)")"
      printf '  "casks": "%s",\n' "$(json_escape "$(cat "$tmpdir/casks.txt" 2>/dev/null || true)")"
      printf '  "taps": "%s",\n' "$(json_escape "$(cat "$tmpdir/taps.txt" 2>/dev/null || true)")"
      printf '  "npm_globals": "%s",\n' "$(json_escape "$(cat "$tmpdir/npm_globals.txt" 2>/dev/null || true)")"
      printf '  "agents": "%s",\n' "$(json_escape "$(cat "$tmpdir/agents.txt" 2>/dev/null || true)")"
      printf '  "dotfiles": "%s",\n' "$(json_escape "$(cat "$tmpdir/dotfiles.txt" 2>/dev/null || true)")"
      printf '  "config_dirs": "%s",\n' "$(json_escape "$(cat "$tmpdir/config_dirs.txt" 2>/dev/null || true)")"
      printf '  "vscode": "%s",\n' "$(json_escape "$(cat "$tmpdir/vscode.txt" 2>/dev/null || true)")"
      printf '  "cursor": "%s",\n' "$(json_escape "$(cat "$tmpdir/cursor.txt" 2>/dev/null || true)")"
      printf '  "dock": "%s"\n' "$(json_escape "$(cat "$tmpdir/dock.txt" 2>/dev/null || true)")"
      printf '}\n'
    } > "$cache_file"
  fi

  # Clear the trap so the local tmpdir variable doesn't leak as unbound
  trap - EXIT
  rm -rf "$tmpdir"

  log_ok "Discovery complete. Cached to $cache_file"
}

# ─────────────────────────────────────────────────────────────
# Cache loader
# ─────────────────────────────────────────────────────────────

# Load discovery.json into exported DISCOVERY_* variables.
# Returns 1 if the cache does not exist.
load_discovery() {
  local cache_file="${DOTFRIEND_CACHE_DIR}/discovery.json"
  if [[ ! -f "$cache_file" ]]; then
    log_warn "No discovery cache found. Run run_discovery first."
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    DISCOVERY_APPS="$(jq -r '.apps // empty' "$cache_file")"
    DISCOVERY_FORMULAE="$(jq -r '.formulae // empty' "$cache_file")"
    DISCOVERY_CASKS="$(jq -r '.casks // empty' "$cache_file")"
    DISCOVERY_TAPS="$(jq -r '.taps // empty' "$cache_file")"
    DISCOVERY_NPM_GLOBALS="$(jq -r '.npm_globals // empty' "$cache_file")"
    DISCOVERY_AGENTS="$(jq -r '.agents // empty' "$cache_file")"
    DISCOVERY_DOTFILES="$(jq -r '.dotfiles // empty' "$cache_file")"
    DISCOVERY_CONFIG_DIRS="$(jq -r '.config_dirs // empty' "$cache_file")"
    DISCOVERY_VSCODE="$(jq -r '.vscode // empty' "$cache_file")"
    DISCOVERY_CURSOR="$(jq -r '.cursor // empty' "$cache_file")"
    DISCOVERY_DOCK="$(jq -r '.dock // empty' "$cache_file")"
  else
    DISCOVERY_APPS="$(json_get_key "$cache_file" apps)"
    DISCOVERY_FORMULAE="$(json_get_key "$cache_file" formulae)"
    DISCOVERY_CASKS="$(json_get_key "$cache_file" casks)"
    DISCOVERY_TAPS="$(json_get_key "$cache_file" taps)"
    DISCOVERY_NPM_GLOBALS="$(json_get_key "$cache_file" npm_globals)"
    DISCOVERY_AGENTS="$(json_get_key "$cache_file" agents)"
    DISCOVERY_DOTFILES="$(json_get_key "$cache_file" dotfiles)"
    DISCOVERY_CONFIG_DIRS="$(json_get_key "$cache_file" config_dirs)"
    DISCOVERY_VSCODE="$(json_get_key "$cache_file" vscode)"
    DISCOVERY_CURSOR="$(json_get_key "$cache_file" cursor)"
    DISCOVERY_DOCK="$(json_get_key "$cache_file" dock)"
  fi

  export DISCOVERY_APPS DISCOVERY_FORMULAE DISCOVERY_CASKS DISCOVERY_TAPS \
    DISCOVERY_NPM_GLOBALS DISCOVERY_AGENTS DISCOVERY_DOTFILES \
    DISCOVERY_CONFIG_DIRS DISCOVERY_VSCODE DISCOVERY_CURSOR DISCOVERY_DOCK
}
