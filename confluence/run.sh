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
  if [[ -n "${CONFLUENCE_INPUT_PAGE_TITLE_STRATEGY:-}" ]]; then
    out+=" --page-title-strategy ${CONFLUENCE_INPUT_PAGE_TITLE_STRATEGY}"
  fi
  if [[ "${CONFLUENCE_INPUT_SKIP_UNCHANGED:-true}" == "false" ]]; then
    out+=" --no-skip-unchanged"
  fi
  if [[ "${CONFLUENCE_INPUT_DRY_RUN:-false}" == "true" ]]; then
    out+=" --dry-run"
  fi
  if [[ "${CONFLUENCE_INPUT_CLEAN:-false}" == "true" ]]; then
    out+=" --clean"
  fi
  if [[ "${CONFLUENCE_INPUT_UPDATE_PARENT_PAGE:-true}" == "false" ]]; then
    out+=" --no-update-parent-page"
  fi
  echo "$out"
}

ensure_asdf_available() {
  if command -v asdf >/dev/null 2>&1; then
    return 0
  fi
  echo >&2 "➡️ Installing asdf ${CONFLUENCE_ASDF_VERSION:-v0.20.0} for repo-toolkit..."
  ASDF_VERSION="${CONFLUENCE_ASDF_VERSION:-v0.20.0}" bash "${CONFLUENCE_ACTION_PATH:?}/../asdf-install/install.sh" >&2
  export PATH="${RUNNER_TEMP:-/tmp}/asdf-bin:${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
  if ! command -v asdf >/dev/null 2>&1; then
    echo >&2 "❌ asdf is unavailable after bootstrap"
    return 1
  fi
}

resolve_repo_toolkit_version() {
  local requested_version="$1"

  if [[ "$requested_version" != "latest" ]]; then
    echo "$requested_version"
    return 0
  fi

  local resolved_version
  resolved_version="$(asdf list all repo-toolkit 2>/dev/null | grep -E '^[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?[[:space:]]*$' | sort -V | tail -n1 | tr -d '[:space:]' || true)"
  if [[ -z "$resolved_version" ]]; then
    echo >&2 "⚠️  Unable to resolve the latest repo-toolkit version from asdf"
    return 1
  fi

  echo "$resolved_version"
}

install_repo_toolkit_via_asdf() {
  # Already resolved via PATH - nothing to do
  if command -v repo-toolkit-confluence >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo >&2 "⚠️  jq not found; cannot install repo-toolkit via asdf (requires jq for GitHub release lookup)."
    return 1
  fi

  if ! command -v node >/dev/null 2>&1; then
    echo >&2 "⚠️  node not found; cannot install repo-toolkit via asdf."
    return 1
  fi

  ensure_asdf_available || return 1

  local toolkit_version="${CONFLUENCE_REPO_TOOLKIT_VERSION:-latest}"
  local install_version="$toolkit_version"
  local toolkit_plugin_url="${CONFLUENCE_REPO_TOOLKIT_PLUGIN_URL:-https://github.com/egose/repo-toolkit.git}"
  CONFLUENCE_RESOLVED_BIN=""

  # Add plugin if not already present
  if ! asdf plugin list 2>/dev/null | grep -q "^repo-toolkit$"; then
    asdf plugin add repo-toolkit "$toolkit_plugin_url" >&2 || true
  fi

  install_version="$(resolve_repo_toolkit_version "$toolkit_version")" || return 1
  if [[ "$toolkit_version" == "latest" ]]; then
    echo >&2 "➡️  repo-toolkit-confluence not found; installing repo-toolkit latest via asdf (resolved to ${install_version})..."
  else
    echo >&2 "➡️  repo-toolkit-confluence not found; installing repo-toolkit ${install_version} via asdf..."
  fi

  if ! asdf install repo-toolkit "$install_version" >&2; then
    echo >&2 "⚠️  asdf repo-toolkit install failed for version ${install_version}"
    return 1
  fi

  local actual_version="$install_version"
  local direct_bin="${ASDF_DATA_DIR:-$HOME/.asdf}/installs/repo-toolkit/${actual_version}/bin/repo-toolkit-confluence"
  if [[ -n "$actual_version" && "$actual_version" != "latest" ]]; then
    # Best effort: asdf >=0.16 uses `set`, older versions used `global`.
    asdf set -u repo-toolkit "$actual_version" >&2 || true
  fi

  local shims_dir="${ASDF_DATA_DIR:-$HOME/.asdf}/shims"
  echo "$shims_dir" >> "$GITHUB_PATH" 2>/dev/null || true
  export PATH="$shims_dir:$PATH"
  asdf reshim repo-toolkit >&2 || asdf reshim >&2 || true

  # Prefer shim when it is actually runnable for the current workspace.
  if asdf which repo-toolkit-confluence >/dev/null 2>&1 && command -v repo-toolkit-confluence >/dev/null 2>&1; then
    echo >&2 "✅ repo-toolkit ${actual_version:-$toolkit_version} installed via asdf"
    return 0
  fi
  if [[ -n "$actual_version" ]]; then
    if [[ -x "$direct_bin" ]]; then
      echo >&2 "✅ repo-toolkit ${actual_version} installed via asdf (direct bin)"
      CONFLUENCE_RESOLVED_BIN="$direct_bin"
      return 0
    fi
  fi

  echo >&2 "⚠️  repo-toolkit-confluence still not found after asdf install"
  return 1
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
  local action_bin="${CONFLUENCE_ACTION_PATH:-}/node_modules/.bin/repo-toolkit-confluence"
  if [[ -x "$action_bin" ]]; then
    echo "$action_bin"
    return 0
  fi

  # 4. PATH lookup (includes asdf shims)
  if command -v repo-toolkit-confluence >/dev/null 2>&1; then
    echo "repo-toolkit-confluence"
    return 0
  fi

  # 5. asdf repo-toolkit fallback (persistent, preferred over npx)
  if install_repo_toolkit_via_asdf; then
    if [[ -n "${CONFLUENCE_RESOLVED_BIN:-}" && -x "${CONFLUENCE_RESOLVED_BIN}" ]]; then
      echo "${CONFLUENCE_RESOLVED_BIN}"
      return 0
    fi
    if command -v repo-toolkit-confluence >/dev/null 2>&1; then
      echo "repo-toolkit-confluence"
      return 0
    fi
  fi

  # 6. npx fallback (downloads on demand; warn loudly)
  echo >&2 "‼️  repo-toolkit-confluence not found; falling back to npx (will download on every run)."
  echo >&2 "   Install it in the consuming repo (pnpm add -D @repo-toolkit/confluence) or pin repo-toolkit-version for better performance."
  echo "npx -y @repo-toolkit/confluence"
}

# Bootstrap node + pnpm via asdf when either is missing on PATH. Mirrors the
# pattern used by pre-commit/run.sh: reuse existing installations as-is, only
# install when the command is unavailable. Adds the asdf shims to GITHUB_PATH
# so subsequent workflow steps also see node/pnpm. For the zero-setup path
# (consumer with only actions/checkout), node is required but pnpm is
# best-effort - repo-toolkit via asdf works without pnpm.
ensure_runtimes() {
  local node_ok=false pnpm_ok=false
  command -v node  >/dev/null 2>&1 && node_ok=true
  command -v pnpm  >/dev/null 2>&1 && pnpm_ok=true

  if [[ "$node_ok" == "true" && "$pnpm_ok" == "true" ]]; then
    echo "✅ node and pnpm already available"
    return 0
  fi

  ensure_asdf_available || exit 1

  if [[ "$node_ok" != "true" ]]; then
    echo "➡️ Installing nodejs ${CONFLUENCE_NODEJS_VERSION:-26.5.0} via asdf..."
    asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git || true
    asdf install nodejs "${CONFLUENCE_NODEJS_VERSION:-26.5.0}"
  fi

  if [[ "$pnpm_ok" != "true" ]]; then
    echo "➡️ Installing pnpm ${CONFLUENCE_PNPM_VERSION:-11.15.0} via asdf..."
    asdf plugin add pnpm https://github.com/jonathanmorley/asdf-pnpm.git || true
    asdf install pnpm "${CONFLUENCE_PNPM_VERSION:-11.15.0}"
  fi

  local shims_dir="${ASDF_DATA_DIR:-$HOME/.asdf}/shims"
  echo "$shims_dir" >> "$GITHUB_PATH" 2>/dev/null || true
  export PATH="$shims_dir:$PATH"

  if ! command -v node >/dev/null 2>&1; then
    echo >&2 "❌ node is unavailable after dependency bootstrap"
    exit 1
  fi
  if ! command -v pnpm >/dev/null 2>&1; then
    echo >&2 "⚠️  pnpm is unavailable after dependency bootstrap (continuing; repo-toolkit via asdf does not require pnpm)"
  fi
}

# Mermaid diagrams (` ```mermaid ` fences) are rendered by the `mmdc` binary
# (@mermaid-js/mermaid-cli). Without it the sync still succeeds but diagrams
# fall back to code macros. `mode` is auto|true|false (default auto).
ensure_mermaid_renderer() {
  local mode="${CONFLUENCE_INPUT_MERMAID:-auto}"

  case "$mode" in
    false|0|no|off)
      echo "ℹ️  Mermaid rendering disabled (mermaid: false); diagrams will sync as code macros"
      return 0
      ;;
    true|1|yes|on)
      ;;
    auto|'')
      ;;
    *)
      echo >&2 "❌ invalid 'mermaid' input (expected auto|true|false), got: ${mode}"
      exit 1
      ;;
  esac

  # Dry-run performs no rendering, so mmdc is never needed there.
  if [[ "${CONFLUENCE_INPUT_DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi

  if command -v mmdc >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$mode" == "auto" || -z "$mode" ]]; then
    if ! mermaid_used_in_folder; then
      return 0
    fi
  fi

  if install_mmdc; then
    return 0
  fi

  if [[ "$mode" == "true" || "$mode" == "1" || "$mode" == "yes" || "$mode" == "on" ]]; then
    echo >&2 "❌ mermaid rendering was explicitly requested (mermaid: true) but mmdc could not be installed"
    exit 1
  fi
  echo >&2 "⚠️  mmdc unavailable; Mermaid blocks will sync as code macros"
}

# True when a ```mermaid fence header exists anywhere under the docs folder,
# so the (heavy, Chrome-bundling) mmdc install only runs when it can matter.
mermaid_used_in_folder() {
  local folder="${CONFLUENCE_INPUT_FOLDER:-docs}"
  grep -rqi --include='*.md' --exclude-dir=node_modules --exclude-dir=.git \
    -E '^[[:space:]]{0,3}```[[:space:]]*mermaid' "$folder" 2>/dev/null
}

install_mmdc() {
  if ! command -v npm >/dev/null 2>&1; then
    echo >&2 "❌ npm not found; cannot install @mermaid-js/mermaid-cli"
    return 1
  fi

  local spec="@mermaid-js/mermaid-cli"
  if [[ -n "${CONFLUENCE_INPUT_MERMAID_CLI_VERSION:-}" && "${CONFLUENCE_INPUT_MERMAID_CLI_VERSION}" != "latest" ]]; then
    spec+="@${CONFLUENCE_INPUT_MERMAID_CLI_VERSION}"
  fi

  # npm 11+ blocks install scripts by default; puppeteer's postinstall
  # downloads the Chrome binary mmdc renders with, so pre-approve only it.
  # Older npm runs postinstall scripts implicitly and needs no flag.
  local allow_scripts_args=()
  local npm_major; npm_major="$(npm --version 2>/dev/null | cut -d. -f1)"
  if [[ "${npm_major:-0}" -ge 11 ]] 2>/dev/null; then
    allow_scripts_args=(--allow-scripts=puppeteer)
  fi

  echo >&2 "➡️ mmdc not found; installing ${spec} for Mermaid rendering (includes a Chrome download via puppeteer)..."
  if ! npm install -g "$spec" "${allow_scripts_args[@]}" >&2; then
    echo >&2 "⚠️  global npm install failed; retrying non-interactively with sudo..."
    sudo -n npm install -g "$spec" "${allow_scripts_args[@]}" >&2 || return 1
  fi

  local npm_bin; npm_bin="$(npm prefix -g)/bin"
  export PATH="$npm_bin:$PATH"
  echo "$npm_bin" >> "$GITHUB_PATH" 2>/dev/null || true
  if command -v asdf >/dev/null 2>&1; then
    asdf reshim nodejs >&2 || true
  fi
  command -v mmdc >/dev/null 2>&1
}

main() {
  if [[ -z "${CONFLUENCE_INPUT_FOLDER:-}" ]]; then
    echo >&2 "❌ 'folder' input is required"
    exit 1
  fi

  # Make sure node (and optionally pnpm) are available before resolving the CLI.
  # For zero-setup consumers, repo-toolkit is auto-installed via asdf when
  # node_modules/.bin is missing.
  ensure_runtimes

  # Resolve the binary BEFORE cd-ing to $cwd so that the workspace-level
  # node_modules/.bin lookup uses the runner workspace rather than the docs
  # folder (which has no node_modules).
  local bin; bin="$(resolve_binary)"

  local cwd="${CONFLUENCE_INPUT_CWD:-${GITHUB_WORKSPACE:-$(pwd)}}"
  cd "$cwd"

  ensure_mermaid_renderer

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
