#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
workspace="$(mktemp -d)"
bin_dir="${workspace}/bin"
asdf_data_dir="${workspace}/asdf"
stdout_file="${workspace}/stdout.log"
stderr_file="${workspace}/stderr.log"
asdf_log="${workspace}/asdf.log"
cli_log="${workspace}/cli.log"
github_path_file="${workspace}/github.path"

cleanup() {
  rm -rf "$workspace"
}

trap cleanup EXIT

mkdir -p "$bin_dir" "${workspace}/docs" "${asdf_data_dir}/shims"

for tool in jq node pnpm; do
  cat > "${bin_dir}/${tool}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod 755 "${bin_dir}/${tool}"
done

cat > "${bin_dir}/asdf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_file="${FAKE_ASDF_LOG:?}"
asdf_data_dir="${ASDF_DATA_DIR:?}"

case "${1:-}" in
  plugin)
    case "${2:-}" in
      list)
        exit 0
        ;;
      add)
        printf 'plugin add %s %s\n' "${3:-}" "${4:-}" >> "$log_file"
        exit 0
        ;;
    esac
    ;;
  list)
    if [[ "${2:-}" == "all" && "${3:-}" == "repo-toolkit" ]]; then
      printf '0.6.0\n0.7.0\n0.14.0\n'
      exit 0
    fi
    if [[ "${2:-}" == "repo-toolkit" ]]; then
      printf '  0.14.0\n'
      exit 0
    fi
    ;;
  install)
    if [[ "${2:-}" == "repo-toolkit" ]]; then
      printf 'install %s\n' "${3:-}" >> "$log_file"
      if [[ "${3:-}" != "0.14.0" ]]; then
        printf 'unexpected repo-toolkit version: %s\n' "${3:-}" >&2
        exit 1
      fi

      install_dir="${asdf_data_dir}/installs/repo-toolkit/${3}/bin"
      mkdir -p "$install_dir"
      cat > "${install_dir}/repo-toolkit-confluence" <<'CLI'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_CLI_LOG:?}"
CLI
      chmod 755 "${install_dir}/repo-toolkit-confluence"

      printf 'Downloading repo-toolkit test fixture\n'
      exit 0
    fi
    ;;
  global)
    printf 'global %s %s\n' "${2:-}" "${3:-}" >> "$log_file"
    exit 0
    ;;
  reshim)
    printf 'reshim %s\n' "${2:-all}" >> "$log_file"
    exit 0
    ;;
esac

printf 'unexpected asdf invocation: %s\n' "$*" >&2
exit 1
EOF
chmod 755 "${bin_dir}/asdf"

(
  cd "$workspace"
  PATH="${bin_dir}:/usr/bin:/bin" \
  ASDF_DATA_DIR="$asdf_data_dir" \
  FAKE_ASDF_LOG="$asdf_log" \
  FAKE_CLI_LOG="$cli_log" \
  GITHUB_PATH="$github_path_file" \
  GITHUB_WORKSPACE="$workspace" \
  CONFLUENCE_ACTION_PATH="${repo_root}/confluence" \
  CONFLUENCE_INPUT_FOLDER='docs' \
  CONFLUENCE_INPUT_DRY_RUN='true' \
  CONFLUENCE_REPO_TOOLKIT_VERSION='latest' \
  bash "${repo_root}/confluence/run.sh" >"$stdout_file" 2>"$stderr_file"
)

if ! grep -Fxq 'install 0.14.0' "$asdf_log"; then
  echo 'expected repo-toolkit latest to resolve to the highest concrete version before install'
  exit 1
fi

if ! grep -Fxq -- '--folder docs --dry-run' "$cli_log"; then
  echo 'expected repo-toolkit-confluence to receive the resolved dry-run arguments'
  exit 1
fi

if ! grep -Fq '🚀 repo-toolkit-confluence --folder docs --dry-run' "$stdout_file"; then
  echo 'expected run.sh to execute the resolved repo-toolkit-confluence binary'
  exit 1
fi

if grep -Fq 'Downloading repo-toolkit test fixture' "$stdout_file"; then
  echo 'expected installer stdout to stay out of the resolved binary command substitution'
  exit 1
fi

printf 'confluence shell tests passed\n'
