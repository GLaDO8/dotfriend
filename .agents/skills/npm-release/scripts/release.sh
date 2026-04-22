#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# npm-release script for dotfriend
# Pre-1.0 versioning: patch/minor -> patch, major -> minor
# ------------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# --- Colors & helpers ---------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { printf "${BLUE}ℹ${NC}  %s\n" "$1"; }
log_ok()    { printf "${GREEN}✔${NC}  %s\n" "$1"; }
log_warn()  { printf "${YELLOW}⚠${NC}  %s\n" "$1"; }
log_error() { printf "${RED}✖${NC}  %s\n" "$1" >&2; }

# --- Prerequisites ------------------------------------------------------------
_check_git() {
  if ! command -v git &>/dev/null; then
    log_error "git is not installed."
    exit 1
  fi

  if ! git rev-parse --git-dir &>/dev/null; then
    log_error "Not a git repository."
    exit 1
  fi

  if ! git remote get-url origin &>/dev/null; then
    log_error "No 'origin' remote configured."
    exit 1
  fi
}

_check_npm() {
  if ! command -v npm &>/dev/null; then
    log_error "npm is not installed."
    exit 1
  fi

  if ! npm whoami &>/dev/null; then
    log_error "You are not logged in to npm. Run: npm login"
    exit 1
  fi
}

# --- Prompt helpers -----------------------------------------------------------
_gum_available() {
  command -v gum &>/dev/null
}

prompt_choice() {
  local prompt_text="$1"
  shift
  local options=("$@")

  if _gum_available; then
    printf '%s\n' "${options[@]}" | gum choose --header "$prompt_text"
  else
    printf '%s\n' "$prompt_text" >&2
    local i=1
    for opt in "${options[@]}"; do
      printf '  %d) %s\n' "$i" "$opt" >&2
      ((i++)) || true
    done
    printf 'Select: ' >&2
    local choice
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      local idx=$((choice - 1))
      if (( idx >= 0 && idx < ${#options[@]} )); then
        printf '%s\n' "${options[$idx]}"
      else
        printf '%s\n' "${options[0]}"
      fi
    else
      printf '%s\n' "$choice"
    fi
  fi
}

prompt_input() {
  local prompt_text="$1"
  local default="${2:-}"

  if _gum_available; then
    if [[ -n "$default" ]]; then
      gum input --placeholder "$default" --prompt "$prompt_text "
    else
      gum input --prompt "$prompt_text "
    fi
  else
    if [[ -n "$default" ]]; then
      printf '%s [%s]: ' "$prompt_text" "$default" >&2
    else
      printf '%s: ' "$prompt_text" >&2
    fi
    local val
    read -r val
    if [[ -z "$val" && -n "$default" ]]; then
      printf '%s\n' "$default"
    else
      printf '%s\n' "$val"
    fi
  fi
}

confirm() {
  local prompt_text="$1"
  if _gum_available; then
    gum confirm "$prompt_text"
  else
    printf '%s [y/N]: ' "$prompt_text" >&2
    local val
    read -r val
    [[ "$val" =~ ^[Yy]$ ]]
  fi
}

# --- Auto-commit message helper -----------------------------------------------

_generate_commit_message() {
  local files
  files="$(git diff --name-only; git diff --cached --name-only)"
  files="$(printf '%s\n' "$files" | sort -u | grep -v '^$')"

  if [[ -z "$files" ]]; then
    printf 'chore: pre-release changes\n'
    return 0
  fi

  local count
  count="$(printf '%s\n' "$files" | wc -l | tr -d ' ')"

  local has_docs=0 has_tests=0 has_config=0 has_source=0 has_deletions=0

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
      *.md|*.txt|README*|CHANGELOG*|LICENSE*)
        has_docs=1
        ;;
      tests/*|*test*|*spec*)
        has_tests=1
        ;;
      package.json|package-lock.json|*.lock|Makefile|*.yml|*.yaml|*.toml|*.json)
        has_config=1
        ;;
      lib/*|src/*|bin/*|scripts/*|*.sh|*.js|*.ts|*.py)
        has_source=1
        ;;
    esac
    if ! git ls-files --error-unmatch "$f" &>/dev/null; then
      : # new file
    fi
  done <<< "$files"

  # Check for deletions
  if git diff --diff-filter=D --name-only | grep -q .; then
    has_deletions=1
  fi

  local type="chore"
  if (( has_source )); then
    type="fix"
  elif (( has_tests )); then
    type="test"
  elif (( has_docs )); then
    type="docs"
  elif (( has_config )); then
    type="chore"
  fi

  # If only one file changed, name it directly
  if [[ "$count" -eq 1 ]]; then
    local file
    file="$(printf '%s' "$files" | head -1)"
    printf '%s: update %s\n' "$type" "$file"
    return 0
  fi

  # Otherwise summarize by directory or category
  local primary_dir
  primary_dir="$(printf '%s\n' "$files" | cut -d/ -f1 | sort | uniq -c | sort -rn | head -1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')"

  if [[ -n "$primary_dir" && "$primary_dir" != "." ]]; then
    if (( has_deletions )); then
      printf '%s: update and clean up %s files\n' "$type" "$primary_dir"
    else
      printf '%s: update %s files\n' "$type" "$primary_dir"
    fi
    return 0
  fi

  printf 'chore: pre-release changes\n'
}

# --- Steps --------------------------------------------------------------------

step_commit_changes() {
  local noninteractive="${1:-}"
  log_info "Checking for uncommitted changes..."

  if git diff --quiet && git diff --cached --quiet; then
    log_ok "No uncommitted changes."
    return 0
  fi

  local msg
  if [[ "$noninteractive" == "1" ]]; then
    msg="$(_generate_commit_message)"
    log_info "Auto-generated commit message: $msg"
  else
    msg="$(prompt_input "Commit message" "chore: pre-release changes")"
    if [[ -z "$msg" ]]; then
      msg="chore: pre-release changes"
    fi
  fi

  git add -A
  git commit -m "$msg"
  log_ok "Committed changes: $msg"
}

step_bump_version() {
  local bump="${1:-}"
  local current
  current="$(node -p "require('./package.json').version" 2>/dev/null || printf '0.0.0')"
  log_info "Current version: ${current}"

  local choice="$bump"
  if [[ -z "$choice" ]]; then
    choice="$(prompt_choice "Bump type" patch minor major manual)"
  fi

  local npm_cmd=""
  case "$choice" in
    patch|minor)
      npm_cmd="npm version patch"
      ;;
    major)
      npm_cmd="npm version minor"
      ;;
    manual)
      local new_version
      new_version="$(prompt_input "Enter new version (e.g. 0.2.0)")"
      if [[ -z "$new_version" ]]; then
        log_error "No version provided."
        exit 1
      fi
      npm_cmd="npm version ${new_version}"
      ;;
    *)
      # Treat anything else as an explicit version (e.g. 0.2.0)
      if [[ "$choice" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        npm_cmd="npm version ${choice}"
      else
        log_error "Unknown bump type: $choice"
        exit 1
      fi
      ;;
  esac

  log_info "Running: $npm_cmd"
  eval "$npm_cmd"

  local new
  new="$(node -p "require('./package.json').version" 2>/dev/null || printf 'unknown')"
  log_ok "Version bumped to ${new}"
}

step_push() {
  log_info "Pushing to origin..."
  git push origin HEAD
  git push origin --tags
  log_ok "Pushed commits and tags."
}

step_publish() {
  log_info "Publishing to npm..."
  npm publish --access public
  log_ok "Published to npm."
}

# --- Main ----------------------------------------------------------------------

main() {
  local bump="${1:-}"
  local noninteractive=0
  if [[ -n "$bump" ]]; then
    noninteractive=1
  fi

  log_info "Starting npm release for dotfriend..."

  _check_git
  _check_npm

  step_commit_changes "$noninteractive"
  step_bump_version "$bump"

  local new_version
  new_version="$(node -p "require('./package.json').version" 2>/dev/null || printf 'unknown')"

  if [[ "$noninteractive" == "0" ]]; then
    if ! confirm "Ready to push and publish v${new_version}?"; then
      log_warn "Aborted by user."
      exit 0
    fi
  fi

  step_push
  step_publish

  log_ok "Release v${new_version} complete!"
}

main "$@"
