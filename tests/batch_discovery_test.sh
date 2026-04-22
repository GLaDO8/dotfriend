#!/usr/bin/env bash
# Test and benchmark the new batched cask API discovery approach
# Usage: ./tests/batch_discovery_test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_DIR/lib/common.sh"

CACHE_DIR="${HOME}/.cache/dotfriend"
ensure_dir "$CACHE_DIR"

CASK_API_JSON="${CACHE_DIR}/cask-api.json"
OLD_APP_INDEX="${CACHE_DIR}/cask-api-app-index.json"
OLD_NAME_INDEX="${CACHE_DIR}/cask-api-name-index.json"

# ── Helpers ──
_fetch_cask_api() {
  local max_age=86400
  if [[ -f "$CASK_API_JSON" ]]; then
    local mtime age
    mtime="$(stat -f %m "$CASK_API_JSON" 2>/dev/null || stat -c %Y "$CASK_API_JSON" 2>/dev/null || printf '0')"
    age="$(($(date +%s) - mtime))"
    if [[ "$age" -lt "$max_age" ]]; then
      printf "API cache fresh (age: %ds)\n" "$age"
      return 0
    fi
  fi
  printf "Fetching cask API...\n"
  curl -fsSL "https://formulae.brew.sh/api/cask.json" -o "$CASK_API_JSON"
  printf "Done. Size: %s\n" "$(wc -c < "$CASK_API_JSON")"
}

# Build old-style indexes
_build_old_indexes() {
  if [[ ! -f "$CASK_API_JSON" ]] || ! command -v jq >/dev/null 2>&1; then
    return 1
  fi
  printf "Building old indexes...\n"
  local t0 t1
  t0="$(date +%s.%N)"
  jq 'reduce .[] as $c ({}; reduce (($c.artifacts // []) | .[] | select(has("app")) | .app | .[] | select(type == "string")) as $a (.; .[$a] = $c.token))' "$CASK_API_JSON" > "$OLD_APP_INDEX"
  jq 'reduce .[] as $c ({}; reduce (($c.name // []) | .[] | select(type == "string")) as $n (.; .[$n] = $c.token))' "$CASK_API_JSON" > "$OLD_NAME_INDEX"
  t1="$(date +%s.%N)"
  printf "Old indexes built in %.2fs\n" "$(echo "$t1 - $t0" | bc)"
}

# Old batch lookup
_old_batch_lookup() {
  if [[ ! -f "$OLD_APP_INDEX" ]] || ! command -v jq >/dev/null 2>&1; then
    return
  fi
  local apps_json
  apps_json="$(jq -R -s 'split("\n") | map(select(length > 0))')"
  [[ -n "$apps_json" ]] || return
  jq \
    --slurpfile app_idx "$OLD_APP_INDEX" \
    --slurpfile name_idx "$OLD_NAME_INDEX" \
    --argjson apps "$apps_json" \
    '
    $apps[] as $app |
    ($app + ".app") as $app_key |
    ($app | ascii_downcase) as $app_lc |
    ($app_key | ascii_downcase) as $app_key_lc |
    ($app_idx[0] | to_entries | map(select(.key | ascii_downcase == $app_key_lc)) | first | .value) as $from_app |
    ($name_idx[0] | to_entries | map(select(.key | ascii_downcase == $app_lc)) | first | .value) as $from_name |
    if $from_app != null then "\($app)|cask:\($from_app)"
    elif $from_name != null then "\($app)|cask:\($from_name)"
    else empty end
    '
}

# NEW: batched lookup against raw API — no indexes
_new_batch_lookup() {
  if [[ ! -f "$CASK_API_JSON" ]] || ! command -v jq >/dev/null 2>&1; then
    return
  fi
  local apps_json
  apps_json="$(jq -R -s 'split("\n") | map(select(length > 0))')"
  [[ -n "$apps_json" ]] || return

  # Single jq invocation:
  # 1. Load API JSON via --slurpfile (avoids shell arg-length limits)
  # 2. Build in-memory lookup maps (artifact app name -> token, display name -> token)
  # 3. Emit matches for each input app
  jq \
    --slurpfile api "$CASK_API_JSON" \
    --argjson apps "$apps_json" \
    '
    # Build artifact-app lookup: lowercase stripped app name -> token
    ($api[0] | reduce .[] as $c ({};
      ($c.token) as $token |
      reduce
        (($c.artifacts // []) | .[] | select(has("app")) | .app | .[] | select(type == "string"))
        as $a (.; .[($a | sub("\\.app$"; "") | ascii_downcase)] = $token)
    )) as $app_map |

    # Build display-name lookup: lowercase name -> token
    ($api[0] | reduce .[] as $c ({};
      ($c.token) as $token |
      reduce
        (($c.name // []) | .[] | select(type == "string"))
        as $n (.; .[($n | ascii_downcase)] = $token)
    )) as $name_map |

    $apps[] as $app |
    ($app | ascii_downcase) as $app_lc |

    if $app_map[$app_lc] != null then
      "\($app)|cask:\($app_map[$app_lc])"
    elif $name_map[$app_lc] != null then
      "\($app)|cask:\($name_map[$app_lc])"
    else
      empty
    end
    '
}

# Collect installed apps
_collect_apps() {
  local -a apps=()
  local app app_name
  for app in /Applications/*.app "${HOME}"/Applications/*.app; do
    [[ -e "$app" ]] || continue
    [[ "$app" == "/Applications/*.app" ]] && continue
    [[ "$app" == "${HOME}/Applications/*.app" ]] && continue
    app_name="$(basename "$app" .app)"
    apps+=("$app_name")
  done
  printf '%s\n' "${apps[@]}"
}

# ── Main ──
printf "=== Batch Discovery Test ===\n\n"

# 1. Fetch API
_fetch_cask_api

# 2. Collect apps
APPS_FILE="$(mktemp)"
_collect_apps > "$APPS_FILE"
APP_COUNT="$(wc -l < "$APPS_FILE" | tr -d ' ')"
printf "Found %d installed apps\n\n" "$APP_COUNT"

if [[ "$APP_COUNT" -eq 0 ]]; then
  printf "No apps found to test with.\n"
  rm -f "$APPS_FILE"
  exit 0
fi

# 3. Build old indexes
_build_old_indexes

# 4. Benchmark old approach
OLD_OUT="$(mktemp)"
printf "Running OLD approach...\n"
OLD_TIME="$(date +%s.%N)"
< "$APPS_FILE" _old_batch_lookup > "$OLD_OUT"
OLD_TIME_END="$(date +%s.%N)"
OLD_DURATION="$(echo "$OLD_TIME_END - $OLD_TIME" | bc)"
OLD_MATCHES="$(wc -l < "$OLD_OUT" | tr -d ' ')"
printf "  Old approach: %.3fs, %d matches\n\n" "$OLD_DURATION" "$OLD_MATCHES"

# 5. Benchmark new approach
NEW_OUT="$(mktemp)"
printf "Running NEW approach...\n"
NEW_TIME="$(date +%s.%N)"
< "$APPS_FILE" _new_batch_lookup > "$NEW_OUT"
NEW_TIME_END="$(date +%s.%N)"
NEW_DURATION="$(echo "$NEW_TIME_END - $NEW_TIME" | bc)"
NEW_MATCHES="$(wc -l < "$NEW_OUT" | tr -d ' ')"
printf "  New approach: %.3fs, %d matches\n\n" "$NEW_DURATION" "$NEW_MATCHES"

# 6. Compare outputs
DIFF_OUT="$(mktemp)"
if diff -u "$OLD_OUT" "$NEW_OUT" > "$DIFF_OUT" 2>&1; then
  printf "✅ Outputs are IDENTICAL\n"
else
  printf "⚠️  Outputs DIFFER:\n"
  cat "$DIFF_OUT"
fi

# 7. Speedup
SPEEDUP="$(echo "scale=2; $OLD_DURATION / $NEW_DURATION" | bc)"
printf "Speedup: ${SPEEDUP}x\n"

# Cleanup
rm -f "$APPS_FILE" "$OLD_OUT" "$NEW_OUT" "$DIFF_OUT"

printf "\n=== Done ===\n"
