#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="/Users/shreyasgupta/local-documents/dotfriend"
TEST_DIR="$(mktemp -d)"

PASS=0
FAIL=0

ok() {
  printf '  ✅ %s\n' "$1"
  ((PASS++)) || true
}

ko() {
  printf '  ❌ %s: %s\n' "$1" "$2"
  ((FAIL++)) || true
}

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

setup_case() {
  local case_dir="$1"
  export HOME="${TEST_DIR}/${case_dir}/home"
  export DOTFRIEND_CACHE_DIR="${HOME}/.cache/dotfriend"
  mkdir -p "$DOTFRIEND_CACHE_DIR"
}

write_selections() {
  local repo_name="$1"
  local dotfiles_json="$2"
  local config_dirs_json="$3"
  local agents_json="$4"

  cat > "${DOTFRIEND_CACHE_DIR}/selections.json" <<EOF
{
  "apps": [],
  "agents": ${agents_json},
  "formulae": [],
  "taps": [],
  "npm_globals": [],
  "dotfiles": ${dotfiles_json},
  "config_dirs": ${config_dirs_json},
  "editors": {"vscode": false, "cursor": false},
  "dock": {"backup": false, "defaults": false},
  "xcode": false,
  "telemetry": false,
  "github": {"repo_name": "${repo_name}", "private": true}
}
EOF
}

source_generator() {
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/lib/common.sh"
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/lib/generate.sh"
}

test_repo_name_and_github_push() {
  setup_case "repo_name"
  write_selections "work-mac" '[".zshrc"]' '[]' '[]'
  printf '# test zshrc\n' > "${HOME}/.zshrc"

  local bin_dir="${TEST_DIR}/repo_name/bin"
  local gh_log="${TEST_DIR}/repo_name/gh.log"
  mkdir -p "$bin_dir"

  cat > "${bin_dir}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${GH_LOG:?}"
case "$1 $2" in
  "auth status")
    exit 0
    ;;
  "api user")
    printf 'tester\n'
    exit 0
    ;;
  "repo view")
    exit 1
    ;;
  "repo create")
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${bin_dir}/gh"

  PATH="${bin_dir}:${PATH}"
  export GH_LOG="$gh_log"

  source_generator

  local output
  if output="$(generate_repo "" false 2>&1)"; then
    ok "generate_repo uses repo name as the default folder"
  else
    ko "generate_repo uses repo name as the default folder" "command failed"
    printf '%s\n' "$output"
    return
  fi

  local repo_dir="${HOME}/work-mac"
  if [[ -d "$repo_dir" ]]; then
    ok "repo directory matches GitHub repo name"
  else
    ko "repo directory matches GitHub repo name" "missing ${repo_dir}"
  fi

  if [[ "$output" == *"unbound variable"* ]]; then
    ko "github push path avoids DRY_RUN crash" "saw unbound variable"
  else
    ok "github push path avoids DRY_RUN crash"
  fi

  if [[ -f "$gh_log" ]] && grep -q 'repo create work-mac --private --source=. --push' "$gh_log"; then
    ok "github create uses the selected repo name"
  else
    ko "github create uses the selected repo name" "gh repo create was not called correctly"
  fi

  if grep -q "${repo_dir}" "${repo_dir}/install.sh"; then
    ko "install.sh stays portable" "embedded source-machine path in install.sh"
  else
    ok "install.sh stays portable"
  fi

  if grep -q "DOTFILES_DIR=\"\${HOME}/work-mac\"" "${repo_dir}/bootstrap.sh"; then
    ok "bootstrap.sh clones into the selected repo folder"
  else
    ko "bootstrap.sh clones into the selected repo folder" "wrong DOTFILES_DIR"
  fi
}

test_agent_and_shared_config_copy() {
  setup_case "agents"
  write_selections "agent-repo" '[".zshrc"]' '[]' '[{"id":"claude","name":"Claude Code"},{"id":"codex","name":"OpenAI Codex"}]'
  printf '# test zshrc\n' > "${HOME}/.zshrc"

  mkdir -p "${HOME}/.claude/hooks" "${HOME}/.codex" "${HOME}/.agents/skills/demo" "${HOME}/.agents/agent-docs"
  printf '# CLAUDE\n' > "${HOME}/.claude/CLAUDE.md"
  printf '{"theme":"dark"}\n' > "${HOME}/.claude/settings.json"
  printf '#!/usr/bin/env bash\n' > "${HOME}/.claude/hooks/pre.sh"
  printf '# AGENTS\n' > "${HOME}/.codex/AGENTS.md"
  printf '# RTK\n' > "${HOME}/.codex/RTK.md"
  printf 'skill\n' > "${HOME}/.agents/skills/demo/SKILL.md"
  printf 'docs\n' > "${HOME}/.agents/agent-docs/readme.md"
  ln -s "${HOME}/.agents/skills" "${HOME}/.codex/skills"
  ln -s "${HOME}/.agents/agent-docs" "${HOME}/.codex/agent-docs"

  source_generator

  local repo_dir="${TEST_DIR}/agents/out"
  if generate_repo "$repo_dir" false >/dev/null 2>&1; then
    ok "agent config generation succeeds"
  else
    ko "agent config generation succeeds" "generate_repo failed"
    return
  fi

  if [[ -f "${repo_dir}/claude/CLAUDE.md" && -f "${repo_dir}/claude/settings.json" && -f "${repo_dir}/claude/hooks/pre.sh" ]]; then
    ok "claude files are copied into the claude folder"
  else
    ko "claude files are copied into the claude folder" "expected Claude files missing"
  fi

  if [[ -f "${repo_dir}/codex/AGENTS.md" && -f "${repo_dir}/codex/RTK.md" ]]; then
    ok "codex files are copied into the codex folder"
  else
    ko "codex files are copied into the codex folder" "expected Codex files missing"
  fi

  if [[ -f "${repo_dir}/agents/skills/demo/SKILL.md" && -f "${repo_dir}/agents/agent-docs/readme.md" ]]; then
    ok "shared ~/.agents content is copied into agents/"
  else
    ko "shared ~/.agents content is copied into agents/" "expected shared agent files missing"
  fi

  if [[ -e "${repo_dir}/codex/skills" || -e "${repo_dir}/codex/agent-docs" ]]; then
    ko "symlinked shared dirs stay out of codex/" "shared symlinked dirs were copied twice"
  else
    ok "symlinked shared dirs stay out of codex/"
  fi
}

test_filtered_recursive_copy_and_layout() {
  setup_case "filtered_copy"
  write_selections "filtered-repo" '[".zshrc",".gitconfig",".npmrc"]' '["opencode"]' '[]'
  printf '# zshrc\n' > "${HOME}/.zshrc"
  printf '[user]\nname = Test\n' > "${HOME}/.gitconfig"
  printf 'prefix=/tmp/test\n' > "${HOME}/.npmrc"

  mkdir -p "${HOME}/.config/opencode/node_modules/pkg" "${HOME}/.config/opencode/cache"
  printf '{"model":"gpt"}\n' > "${HOME}/.config/opencode/settings.json"
  printf 'node_modules/\n' > "${HOME}/.config/opencode/.gitignore"
  printf 'junk\n' > "${HOME}/.config/opencode/node_modules/pkg/index.js"

  source_generator

  local repo_dir="${TEST_DIR}/filtered_copy/out"
  if generate_repo "$repo_dir" false >/dev/null 2>&1; then
    ok "filtered config generation succeeds"
  else
    ko "filtered config generation succeeds" "generate_repo failed"
    return
  fi

  if [[ -f "${repo_dir}/zsh/.zshrc" && -f "${repo_dir}/zsh/.npmrc" ]]; then
    ok "shell dotfiles land in zsh/"
  else
    ko "shell dotfiles land in zsh/" "expected shell files missing"
  fi

  if [[ -f "${repo_dir}/config/git/.gitconfig" ]]; then
    ok "gitconfig lands in config/git/"
  else
    ko "gitconfig lands in config/git/" "missing config/git/.gitconfig"
  fi

  if [[ -f "${repo_dir}/config/opencode/settings.json" ]]; then
    ok "config directories still copy wanted files"
  else
    ko "config directories still copy wanted files" "missing settings.json"
  fi

  if [[ -e "${repo_dir}/config/opencode/node_modules" ]]; then
    ko "node_modules is excluded from copied configs" "node_modules was copied"
  else
    ok "node_modules is excluded from copied configs"
  fi

  if [[ -e "${repo_dir}/config/opencode/.gitignore" ]]; then
    ko ".gitignore files are excluded from copied configs" ".gitignore was copied"
  else
    ok ".gitignore files are excluded from copied configs"
  fi

  if grep -q 'node_modules/' "${repo_dir}/.gitignore"; then
    ok "generated .gitignore still ignores node_modules"
  else
    ko "generated .gitignore still ignores node_modules" "missing node_modules rule"
  fi

  if grep -q '_symlink "\$DOTFILES_DIR/zsh/.zshrc" "\$HOME/.zshrc"' "${repo_dir}/install.sh" && \
     grep -q '_symlink "\$DOTFILES_DIR/config/git/.gitconfig" "\$HOME/.gitconfig"' "${repo_dir}/install.sh"; then
    ok "install.sh points to the new repo layout"
  else
    ko "install.sh points to the new repo layout" "missing portable symlink paths"
  fi
}

printf '\n1. Generation regressions\n'
test_repo_name_and_github_push
test_agent_and_shared_config_copy
test_filtered_recursive_copy_and_layout

printf '\n========================================\n'
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
printf '========================================\n'

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
