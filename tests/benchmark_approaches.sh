#!/usr/bin/env bash
# Benchmark different batch discovery approaches
set -euo pipefail

CASK_API_JSON="${HOME}/.cache/dotfriend/cask-api.json"

# Collect real apps
APPS="$(ls -d /Applications/*.app ~/Applications/*.app 2>/dev/null | while read -r app; do
  [[ -e "$app" ]] || continue
  basename "$app" .app
done)"

APP_COUNT="$(printf '%s\n' "$APPS" | wc -l | tr -d ' ')"
printf "Testing with %d installed apps\n\n" "$APP_COUNT"

# ── Approach 1: Single jq, -R -s stdin, reduce maps ──
approach1() {
  jq --slurpfile api "$CASK_API_JSON" -R -s '
    split("\n") | map(select(length > 0)) as $apps |

    ($api[0] | reduce .[] as $c ({};
      ($c.token) as $token |
      reduce
        (($c.artifacts // []) | .[] | select(has("app")) | .app | .[] | select(type == "string"))
        as $a (.; .[($a | sub("\\.app$"; "") | ascii_downcase)] = $token)
    )) as $app_map |

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

# ── Approach 2: Pre-build app map only, filter names inline ──
approach2() {
  jq --slurpfile api "$CASK_API_JSON" -R -s '
    split("\n") | map(select(length > 0)) as $apps |

    ($api[0] | reduce .[] as $c ({};
      ($c.token) as $token |
      reduce
        (($c.artifacts // []) | .[] | select(has("app")) | .app | .[] | select(type == "string"))
        as $a (.; .[($a | sub("\\.app$"; "") | ascii_downcase)] = $token)
    )) as $app_map |

    $apps[] as $app |
    ($app | ascii_downcase) as $app_lc |

    if $app_map[$app_lc] != null then
      "\($app)|cask:\($app_map[$app_lc])"
    else
      ($api[0][] | select((.name // [])[] | ascii_downcase == $app_lc) | .token) as $from_name |
      if $from_name != null then
        "\($app)|cask:\($from_name)"
      else
        empty
      end
    end
  '
}

# ── Approach 3: Build unified lookup with both artifact names AND display names ──
approach3() {
  jq --slurpfile api "$CASK_API_JSON" -R -s '
    split("\n") | map(select(length > 0)) as $apps |

    ($api[0] | reduce .[] as $c ({};
      ($c.token) as $token |
      # artifact names
      reduce
        (($c.artifacts // []) | .[] | select(has("app")) | .app | .[] | select(type == "string"))
        as $a (.;
          .[($a | sub("\\.app$"; "") | ascii_downcase)] = $token
        ) |
      # display names
      reduce
        (($c.name // []) | .[] | select(type == "string"))
        as $n (.;
          .[($n | ascii_downcase)] = $token
        )
    )) as $lookup |

    $apps[] as $app |
    ($app | ascii_downcase) as $app_lc |

    if $lookup[$app_lc] != null then
      "\($app)|cask:\($lookup[$app_lc])"
    else
      empty
    end
  '
}

# ── Approach 4: Using with_entries instead of reduce (pre-filter API) ──
approach4() {
  jq --slurpfile api "$CASK_API_JSON" -R -s '
    split("\n") | map(select(length > 0)) as $apps |
    ($apps | map(ascii_downcase)) as $apps_lc |

    # Build a flat array of {key: lowercase_name, token: token}
    [
      $api[0][] |
      .token as $token |
      (
        # artifact names
        ((.artifacts // []) | .[] | select(has("app")) | .app | .[] | select(type == "string") |
          {key: (sub("\\.app$"; "") | ascii_downcase), token: $token}),
        # display names
        ((.name // []) | .[] | select(type == "string") |
          {key: (ascii_downcase), token: $token})
      )
    ] |

    # Group by key and pick first token
    group_by(.key) |
    map({(.[0].key): .[0].token}) |
    add as $lookup |

    $apps[] as $app |
    ($app | ascii_downcase) as $app_lc |

    if $lookup[$app_lc] != null then
      "\($app)|cask:\($lookup[$app_lc])"
    else
      empty
    end
  '
}

# ── Benchmark each ──
for i in 1 2 3 4; do
  printf "Approach %d: " "$i"
  OUT="$(mktemp)"
  TIME="$(date +%s.%N)"
  printf '%s\n' "$APPS" | "approach${i}" > "$OUT" 2>/dev/null || true
  TIME_END="$(date +%s.%N)"
  DURATION="$(echo "$TIME_END - $TIME" | bc)"
  MATCHES="$(wc -l < "$OUT" | tr -d ' ')"
  printf "%.3fs, %d matches\n" "$DURATION" "$MATCHES"
  rm -f "$OUT"
done
