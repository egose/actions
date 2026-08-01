#!/usr/bin/env bash

set -euo pipefail

# ----------------------------------------------------------------------------
# Sync a folder of markdown docs to Confluence by invoking repo-toolkit-confluence
# (https://github.com/egose/repo-toolkit/tree/main/packages/confluence).
#
# Inputs are sourced from CONFLUENCE_INPUT_* environment variables (set by
# action.yml, which translates the hyphenated GitHub Action input names into
# bash-safe underscored env vars). Boolean inputs arrive as "true"/"false".
# ----------------------------------------------------------------------------

join_args() {
  local out=""
  if [[ -n "${CONFLUENCE_INPUT_FOLDER:-}" ]]; then
    out+=" --folder ${CONFLUENCE_INPUT_FOLDER}"
  fi
  if [[ -n "${CONFLUENCE_INPUT_USERNAME:-}" ]]; then
    out+=" --username ${CONFLUENCE_INPUT_USERNAME}"
  fi
  local api_token="${CONFLUENCE_INPUT_API_TOKEN:-${CONFLUENCE_INPUT_PASSWORD:-}}"
  if [[ -n "$api_token" ]]; then
    out+=" --api-token ${api_token}"
  fi
  if [[ -n "${CONFLUENCE_INPUT_BASE_URL:-}" ]]; then
    out+=" --confluence-base-url ${CONFLUENCE_INPUT_BASE_URL}"
  fi
  if [[ -n "${CONFLUENCE_INPUT_SPACE_KEY:-}" ]]; then
    out+=" --space-key ${CONFLUENCE_INPUT_SPACE_KEY}"
  fi
  if [[ -n "${CONFLUENCE_INPUT_PARENT_PAGE_ID:-}" ]]; then
    out+=" --parent-page-id ${CONFLUENCE_INPUT_PARENT_PAGE_ID}"
  fi
  if [[ -n "${CONFLUENCE_INPUT_VERSION_MESSAGE:-}" ]]; then
    out+=" --version-message ${CONFLUENCE_INPUT_VERSION_MESSAGE}"
  fi
  if [[ "${CONFLUENCE_INPUT_SKIP_UNCHANGED:-true}" == "false" ]]; then
    out+=" --no-skip-unchanged"
  fi
  if [[ "${CONFLUENCE_INPUT_DRY_RUN:-false}" == "true" ]]; then
    out+=" --dry-run"
  fi
  echo "$out"
}

resolve_binary() {
  # 1. Explicit override
  if [[ -n "${CONFLUENCE_INPUT_BIN:-}" ]]; then
    if [[ -x "${CONFLUENCE_INPUT_BIN}" ]] || command -v "${CONFLUENCE_INPUT_BIN}" >/dev/null 2>&1; then
      echo "${CONFLUENCE_INPUT_BIN}"
      return 0
    fi
    echo >&2 "❌ confluence-bin override not found or not executable: ${CONFLUENCE_INPUT_BIN}"
    return 1
  fi

  # 2. Workspace node_modules/.bin/repo-toolkit-confluence (preferred; matches release-tag pattern)
  local out; out="$(pwd)/node_modules/.bin/repo-toolkit-confluence"
  if [[ -x "$out" ]]; then
    echo "$out"
    return 0
  fi

  # 3. ACTION_PATH node_modules/.bin/repo-toolkit-confluence (fixture-driven tests)
  local action_bin="${ACTION_PATH:-}/node_modules/.bin/repo-toolkit-confluence"
  if [[ -x "$action_bin" ]]; then
    echo "$action_bin"
    return 0
  fi

  # 4. PATH lookup
  if command -v repo-toolkit-confluence >/dev/null 2>&1; then
    echo "repo-toolkit-confluence"
    return 0
  fi

  # 5. npx fallback (downloads on demand; warn loudly)
  echo >&2 "‼️  repo-toolkit-confluence not found; falling back to npx (will download on every run)."
  echo >&2 "   Install it in the consuming repo (pnpm add -D @repo-toolkit/confluence) for better performance."
  echo "npx -y @repo-toolkit/confluence"
}

main() {
  if [[ -z "${CONFLUENCE_INPUT_FOLDER:-}" ]]; then
    echo >&2 "❌ 'folder' input is required"
    exit 1
  fi

  # Resolve the binary BEFORE cd-ing to $cwd so that the workspace-level
  # node_modules/.bin lookup uses the runner workspace rather than the docs
  # folder (which has no node_modules).
  local bin; bin="$(resolve_binary)"

  local cwd="${CONFLUENCE_INPUT_CWD:-${GITHUB_WORKSPACE:-$(pwd)}}"
  cd "$cwd"

  if [[ "${CONFLUENCE_INPUT_DRY_RUN:-false}" != "true" ]]; then
    # In real mode, fail fast when required Confluence credentials are missing.
    if [[ -z "${CONFLUENCE_INPUT_USERNAME:-}" ]]; then echo >&2 "❌ 'username' is required (non-dry-run)"; exit 1; fi
    if [[ -z "${CONFLUENCE_INPUT_API_TOKEN:-${CONFLUENCE_INPUT_PASSWORD:-}}" ]]; then echo >&2 "❌ 'api-token' (or 'password') is required (non-dry-run)"; exit 1; fi
    if [[ -z "${CONFLUENCE_INPUT_BASE_URL:-}" ]]; then echo >&2 "❌ 'confluence-base-url' is required (non-dry-run)"; exit 1; fi
    if [[ -z "${CONFLUENCE_INPUT_SPACE_KEY:-}" ]]; then echo >&2 "❌ 'space-key' is required (non-dry-run)"; exit 1; fi
    if [[ -z "${CONFLUENCE_INPUT_PARENT_PAGE_ID:-}" ]]; then echo >&2 "❌ 'parent-page-id' is required (non-dry-run)"; exit 1; fi
    if ! [[ "${CONFLUENCE_INPUT_PARENT_PAGE_ID}" =~ ^[0-9]+$ ]]; then
      echo >&2 "❌ 'parent-page-id' must be numeric, got: ${CONFLUENCE_INPUT_PARENT_PAGE_ID}"
      exit 1
    fi
  fi

  local args; args="$(join_args)"

  echo "🚀 ${bin}${args}"
  # The pnpm/npm bin shims ship with a `#!/bin/sh` shebang and are executable,
  # so a direct exec honours them (matches the release-tag action's convention
  # of invoking `node_modules/.bin/release-it` directly). The `npx ...` and
  # bare `repo-toolkit-confluence` (PATH) cases are already valid commands.
  # shellcheck disable=SC2086
  $bin $args
}

main "$@"
