#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
workspace="$(mktemp -d)"
bin_dir="${workspace}/bin"
log_file="${workspace}/install.log"

cleanup() {
  rm -rf "$workspace"
}

trap cleanup EXIT

mkdir -p "$bin_dir" "${workspace}/apps/app one" "${workspace}/apps/app two"
# A target that is itself a pnpm workspace root (has pnpm-workspace.yaml) must
# NOT receive --ignore-workspace; this is the monorepo case.
mkdir -p "${workspace}/mono"

for manager in npm pnpm yarn; do
  cat > "${bin_dir}/${manager}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [ "${manager}" = 'yarn' ] && [ "\${1:-}" = '--version' ]; then
  printf '1.22.22\n'
  exit 0
fi

printf '%s|%s\n' "${manager}" "\$PWD::\$*" >> "${log_file}"
EOF
  chmod 755 "${bin_dir}/${manager}"
done

run_case() {
  local manager="$1"
  local frozen="$2"
  local ignore_scripts="$3"
  local expected_one="$4"
  local expected_two="$5"

  : > "$log_file"
  PATH="${bin_dir}:$PATH" \
  PACKAGE_MANAGER="$manager" \
  PACKAGE_FROZEN="$frozen" \
  PACKAGE_IGNORE_SCRIPTS="$ignore_scripts" \
  PACKAGE_PATHS=$'apps/app one\napps/app two' \
  bash "${repo_root}/scripts/install-packages.sh"

  mapfile -t lines < "$log_file"
  if [ "${#lines[@]}" -ne 2 ]; then
    echo "expected two install invocations for ${manager}, got ${#lines[@]}"
    exit 1
  fi

  if [ "${lines[0]}" != "${manager}|${workspace}/apps/app one::${expected_one}" ]; then
    echo "unexpected first invocation for ${manager}: ${lines[0]}"
    exit 1
  fi

  if [ "${lines[1]}" != "${manager}|${workspace}/apps/app two::${expected_two}" ]; then
    echo "unexpected second invocation for ${manager}: ${lines[1]}"
    exit 1
  fi
}

run_workspace_case() {
  local manager="$1"
  local frozen="$2"
  local ignore_scripts="$3"
  local expected="$4"

  : > "$log_file"
  touch "${workspace}/mono/pnpm-workspace.yaml"
  PATH="${bin_dir}:$PATH" \
  PACKAGE_MANAGER="$manager" \
  PACKAGE_FROZEN="$frozen" \
  PACKAGE_IGNORE_SCRIPTS="$ignore_scripts" \
  PACKAGE_PATHS='mono' \
  bash "${repo_root}/scripts/install-packages.sh"

  mapfile -t lines < "$log_file"
  if [ "${#lines[@]}" -ne 1 ]; then
    echo "expected one install invocation for ${manager} workspace root, got ${#lines[@]}"
    rm -f "${workspace}/mono/pnpm-workspace.yaml"
    exit 1
  fi
  rm -f "${workspace}/mono/pnpm-workspace.yaml"

  if [ "${lines[0]}" != "${manager}|${workspace}/mono::${expected}" ]; then
    echo "unexpected invocation for ${manager} workspace root: ${lines[0]}"
    echo "expected: ${manager}|${workspace}/mono::${expected}"
    exit 1
  fi
}

run_npm_frozen_failure_case() {
  cat > "${bin_dir}/npm" <<EOF
#!/usr/bin/env bash
set -euo pipefail

printf '%s|%s\n' npm "\$PWD::\$*" >> "${log_file}"
exit 1
EOF
  chmod 755 "${bin_dir}/npm"

  : > "$log_file"
  if PATH="${bin_dir}:$PATH" \
    PACKAGE_MANAGER='npm' \
    PACKAGE_FROZEN='true' \
    PACKAGE_IGNORE_SCRIPTS='false' \
    PACKAGE_PATHS='apps/app one' \
    bash "${repo_root}/scripts/install-packages.sh" >"${workspace}/failure.out" 2>&1; then
    echo 'expected frozen npm install to fail'
    exit 1
  fi

  if ! grep -Fq "'frozen: true' uses 'npm ci'" "${workspace}/failure.out"; then
    echo 'expected frozen npm failure guidance in output'
    exit 1
  fi

  if ! grep -Fq "${workspace}/apps/app one" "${workspace}/failure.out"; then
    echo 'expected failing target path in output'
    exit 1
  fi
}

cd "$workspace"

run_case npm true true 'ci --ignore-scripts' 'ci --ignore-scripts'
run_case pnpm false false 'install --ignore-workspace' 'install --ignore-workspace'
run_case pnpm true false 'install --ignore-workspace --frozen-lockfile' 'install --ignore-workspace --frozen-lockfile'
run_case pnpm false true 'install --ignore-workspace --ignore-scripts' 'install --ignore-workspace --ignore-scripts'
run_case pnpm true true 'install --ignore-workspace --frozen-lockfile --ignore-scripts' 'install --ignore-workspace --frozen-lockfile --ignore-scripts'
run_case yarn false true 'install --ignore-scripts' 'install --ignore-scripts'

run_workspace_case pnpm false false 'install'
run_workspace_case pnpm true false 'install --frozen-lockfile'
run_workspace_case pnpm false true 'install --ignore-scripts'
run_workspace_case pnpm true true 'install --frozen-lockfile --ignore-scripts'
run_npm_frozen_failure_case

printf 'install-packages helper tests passed\n'
