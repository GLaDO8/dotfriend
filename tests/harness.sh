#!/usr/bin/env bash
# dotfriend test harness — shared utilities for test agents
# shellcheck shell=bash

set -euo pipefail

TEST_DIR="${TEST_DIR:-$(mktemp -d)}"
DOTFRIEND_ROOT="${DOTFRIEND_ROOT:-/Users/shreyasgupta/local-documents/dotfriend}"
REPORT_FILE="${TEST_DIR}/report.md"

ensure_dir() { [[ -d "$1" ]] || mkdir -p "$1"; }

log_test() {
  local status="$1" test_name="$2" details="${3:-}"
  local icon="✅"
  [[ "$status" == "FAIL" ]] && icon="❌"
  [[ "$status" == "WARN" ]] && icon="⚠️"
  printf "%s %s" "$icon" "$test_name"
  [[ -n "$details" ]] && printf " — %s" "$details"
  printf "\n"
  printf "| %s | %s | %s |\n" "$status" "$test_name" "${details:-}" >> "$REPORT_FILE"
}

init_report() {
  ensure_dir "$TEST_DIR"
  printf "# dotfriend Test Report\n\n" > "$REPORT_FILE"
  printf "| Status | Test | Details |\n" >> "$REPORT_FILE"
  printf "|--------|------|---------|\n" >> "$REPORT_FILE"
}

# Create a sandboxed HOME with mock dotfiles
setup_sandbox_home() {
  local home_dir="${TEST_DIR}/fake_home"
  ensure_dir "$home_dir"
  export HOME="$home_dir"
  export DOTFRIEND_CACHE_DIR="${home_dir}/.cache/dotfriend"
  ensure_dir "$DOTFRIEND_CACHE_DIR"
  return 0
}

# Create mock discovery cache
mock_discovery_cache() {
  local cache="${DOTFRIEND_CACHE_DIR}/discovery.json"
  cat > "$cache" <<'EOF'
{
  "apps": "Safari|manual\nSpotify|cask:spotify\nXcode|mas:xcode,id:497799835",
  "formulae": "git|Distributed revision control system\nnode|Platform built on V8 JavaScript runtime",
  "casks": "spotify\ndiscord",
  "taps": "homebrew/cask",
  "npm_globals": "typescript@5.0.0\n@openai/codex@1.0.0",
  "agents": "claude|Claude Code|~/.claude|found\ncodex|OpenAI Codex|~/.codex|found",
  "dotfiles": ".zshrc\n.gitconfig\n.npmrc",
  "config_dirs": "karabiner",
  "vscode": "settings:/Users/test/Library/Application Support/Code/User/settings.json\nextensions:\nms-python.python\nbradlc.vscode-tailwindcss",
  "cursor": "settings:missing",
  "dock": "Finder\t/Applications/Finder.app\nSafari\t/Applications/Safari.app"
}
EOF
}

# Create mock selections cache
mock_selections_cache() {
  local cache="${DOTFRIEND_CACHE_DIR}/selections.json"
  cat > "$cache" <<'EOF'
{
  "apps": [
    {"name":"Safari","cask":"","source":"manual"},
    {"name":"Spotify","cask":"spotify","source":"cask"}
  ],
  "agents": [
    {"id":"claude","name":"Claude Code"},
    {"id":"codex","name":"OpenAI Codex"}
  ],
  "formulae": ["git", "node"],
  "taps": ["homebrew/cask"],
  "npm_globals": ["typescript@5.0.0", "@openai/codex@1.0.0"],
  "dotfiles": [".zshrc", ".gitconfig"],
  "config_dirs": ["karabiner"],
  "editors": {"vscode": true, "cursor": false},
  "dock": {"backup": true, "defaults": false},
  "xcode": true,
  "telemetry": true,
  "github": {"repo_name": "dotfiles", "private": true}
}
EOF
}

# Create mock agent tool configs
mock_agent_configs() {
  ensure_dir "${HOME}/.claude"
  printf "# Test CLAUDE.md\n" > "${HOME}/.claude/CLAUDE.md"
  printf '{"test": true}\n' > "${HOME}/.claude/settings.json"
  ensure_dir "${HOME}/.claude/hooks"
  printf "#!/bin/bash\n" > "${HOME}/.claude/hooks/test.sh"

  ensure_dir "${HOME}/.codex"
  printf "# Test AGENTS.md\n" > "${HOME}/.codex/AGENTS.md"
}

# Create mock dotfiles
mock_dotfiles() {
  printf "# Test zshrc\n" > "${HOME}/.zshrc"
  printf "[user]\nname = Test\n" > "${HOME}/.gitconfig"
  printf "prefix=/test\n" > "${HOME}/.npmrc"
}

# Create a mock dotfiles repo for sync testing
mock_dotfiles_repo() {
  local repo="${TEST_DIR}/dotfiles_repo"
  ensure_dir "$repo"
  ensure_dir "${repo}/config"
  ensure_dir "${repo}/vscode"
  ensure_dir "${repo}/scripts"

  printf "tap \"homebrew/cask\"\n" > "${repo}/Brewfile"
  printf "git\nnode\n" > "${repo}/scripts/npm-globals.txt"
  printf "{\"test\": true}\n" > "${repo}/vscode/settings.json"
  printf "ms-python.python\n" > "${repo}/vscode/extensions.txt"

  (cd "$repo" && git init && git add . && git commit -m "init" 2>/dev/null || true)
  printf '%s' "$repo"
}

# Run a test function and capture results
run_test() {
  local test_name="$1"
  shift
  if "$@" 2>&1; then
    log_test "PASS" "$test_name" ""
    return 0
  else
    local exit_code=$?
    log_test "FAIL" "$test_name" "exit code $exit_code"
    return 1
  fi
}

# Source dotfriend with a custom HOME
source_dotfriend() {
  # shellcheck disable=SC1090
  source "$DOTFRIEND_ROOT/dotfriend" "$@"
}

export -f ensure_dir log_test init_report setup_sandbox_home
export -f mock_discovery_cache mock_selections_cache mock_agent_configs
export -f mock_dotfiles mock_dotfiles_repo run_test source_dotfriend
export TEST_DIR DOTFRIEND_ROOT REPORT_FILE
