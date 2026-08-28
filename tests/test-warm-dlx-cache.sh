#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
workspace="$(mktemp -d)"
bin_dir="${workspace}/bin"
log_file="${workspace}/dlx.log"

cleanup() {
  rm -rf "$workspace"
}

trap cleanup EXIT

mkdir -p "$bin_dir" "${workspace}/apps/web" "${workspace}/tools"

cat > "${bin_dir}/pnpm" <<EOF
#!/usr/bin/env bash
set -euo pipefail

printf 'dlx %s @ %s\n' "\$2" "\$PWD" >> "${log_file}"

# Simulate a tool that fails on --help/--version
if [ "\$2" = 'broken-cli' ]; then
  exit 1
fi

exit 0
EOF
chmod 755 "${bin_dir}/pnpm"

run_case() {
  local dlxtools="$1"
  local expected_count="$2"

  : > "$log_file"
  PATH="${bin_dir}:$PATH" \
  DLX_TOOLS="$dlxtools" \
  bash -c 'cd "$1" && bash "$2"' _ "$workspace" "${repo_root}/scripts/warm-dlx-cache.sh"

  mapfile -t lines < "$log_file"
  if [ "${#lines[@]}" -ne "$expected_count" ]; then
    echo "expected ${expected_count} dlx invocations, got ${#lines[@]}: ${lines[*]:-}"
    exit 1
  fi
}

# Bare package names run in the workspace root
run_case $'turbo\ncowsay@1 fortune' 3

if [ "${lines[0]}" != "dlx turbo @ ${workspace}" ] || \
   [ "${lines[1]}" != "dlx cowsay@1 @ ${workspace}" ] || \
   [ "${lines[2]}" != "dlx fortune @ ${workspace}" ]; then
  echo "unexpected root invocations: ${lines[*]}"
  exit 1
fi

# Path-prefixed entries run with that directory as cwd
run_case $'apps/web: vite prettier\ntools: eslint' 3

if [ "${lines[0]}" != "dlx vite @ ${workspace}/apps/web" ] || \
   [ "${lines[1]}" != "dlx prettier @ ${workspace}/apps/web" ] || \
   [ "${lines[2]}" != "dlx eslint @ ${workspace}/tools" ]; then
  echo "unexpected path-scoped invocations: ${lines[*]}"
  exit 1
fi

# Blank lines are skipped and missing directories are skipped
run_case $'\nmissing/dir: foo\n turbo ' 1

# A tool that fails both --help and --version must fail the script
if PATH="${bin_dir}:$PATH" DLX_TOOLS='broken-cli' \
  bash -c 'cd "$1" && bash "$2"' _ "$workspace" "${repo_root}/scripts/warm-dlx-cache.sh" 2>/dev/null; then
  echo "expected failure for broken-cli"
  exit 1
fi

echo "warm-dlx-cache tests passed"
