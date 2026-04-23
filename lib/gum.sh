#!/usr/bin/env bash
# dotfriend — Gum wrappers. Gum is a hard requirement for dotfriend.
# shellcheck shell=bash
#
# The entry script (dotfriend) guarantees Gum is installed before
# sourcing this file. The plain-bash fallbacks below are kept only
# for robustness during testing (e.g. GUM_AVAILABLE=false).

# Source common.sh first
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ─────────────────────────────────────────────────────────────
# Gum detection
# ─────────────────────────────────────────────────────────────

if [[ -z "${GUM_AVAILABLE:-}" ]]; then
  GUM_AVAILABLE=false
  if command -v gum >/dev/null 2>&1; then
    GUM_AVAILABLE=true
  fi
fi

# ─────────────────────────────────────────────────────────────
# Gum theme overrides
# ─────────────────────────────────────────────────────────────

# Make the cursor white so unchecked items don't appear pink.
# Selected items still use the default pink (212) via --selected.foreground.
export GUM_CHOOSE_CURSOR_FOREGROUND=""

# Show Gum's built-in footer for multi-select lists.
export GUM_CHOOSE_SHOW_HELP="true"

# Auto-install gum via Homebrew. Called by the entry script before
# anything else runs. Hard-exits if installation fails.
gum_ensure() {
  if [[ "$GUM_AVAILABLE" == true ]]; then
    return 0
  fi
  if has_brew; then
    log_info "Gum not found. Installing via Homebrew..."
    brew install gum
    if command -v gum >/dev/null 2>&1; then
      GUM_AVAILABLE=true
      return 0
    fi
  fi
  log_error "Gum could not be installed. dotfriend requires Gum to run."
  exit 1
}

# ─────────────────────────────────────────────────────────────
# Style helpers
# ─────────────────────────────────────────────────────────────

gum_style() {
  if [[ "$GUM_AVAILABLE" == true ]]; then
    gum style "$@"
  else
    # Fallback: just print the last argument (the text)
    local text=""
    while [[ $# -gt 0 ]]; do
      text="$1"
      shift
    done
    printf '%s\n' "$text"
  fi
}

gum_join() {
  if [[ "$GUM_AVAILABLE" == true ]]; then
    gum join "$@"
  else
    printf '%s ' "$@"
    printf '\n'
  fi
}

# ─────────────────────────────────────────────────────────────
# Input primitives
# ─────────────────────────────────────────────────────────────

gum_input() {
  if [[ "$GUM_AVAILABLE" == true ]]; then
    gum input "$@"
  else
    local placeholder="" default=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --placeholder) placeholder="$2"; shift 2 ;;
        --value) default="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    prompt_input "${placeholder:-Enter value}" "$default"
  fi
}

gum_confirm() {
  if [[ "$GUM_AVAILABLE" == true ]]; then
    local args=() prompt_text=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --prompt) prompt_text="$2"; shift 2 ;;
        --affirmative|--negative|--timeout)
          args+=("$1" "$2"); shift 2 ;;
        --*)
          args+=("$1"); shift ;;
        *)
          args+=("$1"); shift ;;
      esac
    done
    if [[ -n "$prompt_text" ]]; then
      gum confirm "$prompt_text" "${args[@]}"
    else
      gum confirm "${args[@]}"
    fi
  else
    local msg="Continue?"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --prompt|--affirmative) msg="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    prompt_confirm "$msg"
  fi
}

# ─────────────────────────────────────────────────────────────
# Choose / multi-select
# ─────────────────────────────────────────────────────────────

gum_choose() {
  if [[ "$GUM_AVAILABLE" == true ]]; then
    local args=() items=() header=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-limit)
          args+=("$1")
          shift
          ;;
        --header)
          header="$2"
          shift 2
          ;;
        --*=*)
          args+=("$1")
          shift
          ;;
        --*)
          args+=("$1")
          if [[ $# -ge 2 && "$2" != --* ]]; then
            args+=("$2")
            shift 2
          else
            shift
          fi
          ;;
        *)
          items+=("$1")
          shift
          ;;
      esac
    done

    if [[ -n "$header" ]]; then
      args+=(--header "$header")
    fi

    gum choose "${args[@]}" "${items[@]}"
  else
    local items=() selected=() header=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-limit) shift ;;
        --selected) selected+=("$2"); shift 2 ;;
        --header) header="$2"; shift 2 ;;
        --*) shift ;;
        *) items+=("$1"); shift ;;
      esac
    done
    [[ -n "$header" ]] && printf '%s\n' "$header" >&2
    local i=1 opt
    for opt in "${items[@]}"; do
      printf "  %d) %s\n" "$i" "$opt" >&2
      ((i++))
    done
    if [[ "$no_limit" == true ]]; then
      printf "Enter numbers (space-separated, or 'all'): " >&2
      read -r response
      if [[ "$response" == "all" ]]; then
        printf '%s\n' "${items[@]}"
      else
        for num in $response; do
          printf '%s\n' "${items[$((num-1))]}"
        done
      fi
    else
      printf "Selection: " >&2
      read -r response
      printf '%s\n' "${items[$((response-1))]}"
    fi
  fi
}

# ─────────────────────────────────────────────────────────────
# Spin / progress
# ─────────────────────────────────────────────────────────────

gum_spin() {
  if [[ "$GUM_AVAILABLE" == true ]]; then
    gum spin "$@"
  else
    # Fallback: just run the command
    local cmd=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --spinner|--title|--timeout|--align) shift 2 ;;  # consume flag + argument
        --show-output|--show-error|--show-stdout|--show-stderr) shift ;;
        --) shift; break ;;
        *) cmd+=("$1"); shift ;;
      esac
    done
    # Any remaining args after -- are also part of the command
    while [[ $# -gt 0 ]]; do
      cmd+=("$1"); shift
    done
    "${cmd[@]}"
  fi
}

# ─────────────────────────────────────────────────────────────
# Filter / fuzzy search
# ─────────────────────────────────────────────────────────────

gum_filter() {
  if [[ "$GUM_AVAILABLE" == true ]]; then
    gum filter "$@"
  else
    # Fallback: just cat stdin
    cat
  fi
}

# ─────────────────────────────────────────────────────────────
# Paging / table
# ─────────────────────────────────────────────────────────────

gum_pager() {
  if [[ "$GUM_AVAILABLE" == true ]]; then
    gum pager "$@"
  else
    cat
  fi
}

# ─────────────────────────────────────────────────────────────
# Write (form)
# ─────────────────────────────────────────────────────────────

gum_write() {
  if [[ "$GUM_AVAILABLE" == true ]]; then
    gum write "$@"
  else
    local placeholder="" default=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --placeholder) placeholder="$2"; shift 2 ;;
        --value) default="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    printf "%s (Ctrl-D to finish):\n" "${placeholder:-Enter text}"
    cat
  fi
}
