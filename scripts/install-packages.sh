#!/usr/bin/env bash

set -euo pipefail

run_install_command() {
  if "$@"; then
    return 0
  fi

  echo "❌ ${PACKAGE_MANAGER} install failed in $(pwd)" >&2

  if [ "${PACKAGE_MANAGER}" = 'npm' ] && [ "${PACKAGE_FROZEN}" = 'true' ]; then
    echo "   'frozen: true' uses 'npm ci', which requires package-lock.json to already be in sync with package.json." >&2
    echo "   Run 'npm install' in this directory and commit the updated lockfile, or set 'frozen: false'." >&2
  fi

  exit 1
}

install_target() {
  case "${PACKAGE_MANAGER}" in
    npm)
      if [ "${PACKAGE_FROZEN}" = 'true' ] && [ "${PACKAGE_IGNORE_SCRIPTS}" = 'true' ]; then
        run_install_command npm ci --ignore-scripts
      elif [ "${PACKAGE_FROZEN}" = 'true' ]; then
        run_install_command npm ci
      elif [ "${PACKAGE_IGNORE_SCRIPTS}" = 'true' ]; then
        run_install_command npm install --ignore-scripts
      else
        run_install_command npm install
      fi
      ;;
    pnpm)
      # Pass --ignore-workspace only when the target directory is not itself a
      # pnpm workspace root. This protects standalone projects nested under a
      # parent pnpm-workspace.yaml (so pnpm doesn't walk up and mutate the
      # parent's lockfile), while letting genuine workspace roots install their
      # full package set normally.
      workspace_flags=()
      if [ ! -f 'pnpm-workspace.yaml' ]; then
        workspace_flags+=(--ignore-workspace)
      fi

      if [ "${PACKAGE_FROZEN}" = 'true' ] && [ "${PACKAGE_IGNORE_SCRIPTS}" = 'true' ]; then
        run_install_command pnpm install "${workspace_flags[@]}" --frozen-lockfile --ignore-scripts
      elif [ "${PACKAGE_FROZEN}" = 'true' ]; then
        run_install_command pnpm install "${workspace_flags[@]}" --frozen-lockfile
      elif [ "${PACKAGE_IGNORE_SCRIPTS}" = 'true' ]; then
        run_install_command pnpm install "${workspace_flags[@]}" --ignore-scripts
      else
        run_install_command pnpm install "${workspace_flags[@]}"
      fi
      ;;
    yarn)
      if [ "${PACKAGE_IGNORE_SCRIPTS}" = 'true' ]; then
        yarn_version="$(yarn --version)"
        yarn_major="${yarn_version%%.*}"

        if [ "${PACKAGE_FROZEN}" = 'true' ] && [ "${yarn_major}" -ge 2 ] 2>/dev/null; then
          run_install_command env YARN_ENABLE_SCRIPTS=false yarn install --frozen-lockfile
        elif [ "${PACKAGE_FROZEN}" = 'true' ]; then
          run_install_command yarn install --frozen-lockfile --ignore-scripts
        elif [ "${yarn_major}" -ge 2 ] 2>/dev/null; then
          run_install_command env YARN_ENABLE_SCRIPTS=false yarn install
        else
          run_install_command yarn install --ignore-scripts
        fi
      elif [ "${PACKAGE_FROZEN}" = 'true' ]; then
        run_install_command yarn install --frozen-lockfile
      else
        run_install_command yarn install
      fi
      ;;
    *)
      echo "❌ Unsupported package manager: ${PACKAGE_MANAGER}"
      exit 1
      ;;
  esac
}

workspace_dir="$(pwd)"

while IFS= read -r path || [ -n "$path" ]; do
  if [ -z "$path" ]; then
    continue
  fi

  target="${workspace_dir}/${path}"
  echo "${target}"

  if [ ! -d "${target}" ]; then
    continue
  fi

  cd "${target}"
  install_target
done <<< "${PACKAGE_PATHS}"
