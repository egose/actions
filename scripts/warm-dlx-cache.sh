#!/usr/bin/env bash

set -euo pipefail

# Warm the pnpm dlx cache for ad-hoc CLI tools that are not declared in any
# package.json. Each line of DLX_TOOLS is either:
#   pkg1 pkg2            -> tools cached (run in the workspace root)
#   some/dir: pkg1 pkg2  -> tools cached with that directory as cwd
# Warming means downloading the tool into the dlx cache; the tool's own
# invocation is allowed to fail as long as the download succeeded.

run_tool() {
  local pkg="$1"

  if pnpm dlx "$pkg" --help > /dev/null 2>&1; then
    return 0
  fi

  if pnpm dlx "$pkg" --version > /dev/null 2>&1; then
    return 0
  fi

  echo "❌ Failed to cache tool via 'pnpm dlx ${pkg}' in $(pwd)" >&2
  echo "   Make sure the package name (and version, if pinned) is correct." >&2
  return 1
}

workspace_dir="$(pwd)"

while IFS= read -r line || [ -n "$line" ]; do
  if [ -z "$line" ]; then
    continue
  fi

  path='.'
  pkgs="$line"
  case "$line" in
    *:*)
      path="${line%%:*}"
      pkgs="${line#*:}"
      ;;
  esac

  # shellcheck disable=SC2086 # intentional word splitting for the package list
  set -- $pkgs
  if [ "$#" -eq 0 ]; then
    continue
  fi

  target="${workspace_dir}/${path}"
  if [ ! -d "$target" ]; then
    echo "⚠️ Skipping missing directory: ${path}" >&2
    continue
  fi

  cd "$target"
  for pkg in "$@"; do
    echo "Caching tool '${pkg}' (${path})"
    run_tool "$pkg"
  done
done <<< "${DLX_TOOLS}"
