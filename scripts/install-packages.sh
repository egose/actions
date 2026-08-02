#!/usr/bin/env bash

set -euo pipefail

install_target() {
  case "${PACKAGE_MANAGER}" in
    npm)
      if [ "${PACKAGE_FROZEN}" = 'true' ] && [ "${PACKAGE_IGNORE_SCRIPTS}" = 'true' ]; then
        npm ci --ignore-scripts
      elif [ "${PACKAGE_FROZEN}" = 'true' ]; then
        npm ci
      elif [ "${PACKAGE_IGNORE_SCRIPTS}" = 'true' ]; then
        npm install --ignore-scripts
      else
        npm install
      fi
      ;;
    pnpm)
      # Always pass --ignore-workspace so installs run against the target
      # directory's own package.json/lockfile, even when a parent directory
      # contains a pnpm-workspace.yaml. Without this, pnpm walks up to the
      # nearest workspace root and installs/writes the lockfile there.
      if [ "${PACKAGE_FROZEN}" = 'true' ] && [ "${PACKAGE_IGNORE_SCRIPTS}" = 'true' ]; then
        pnpm install --ignore-workspace --frozen-lockfile --ignore-scripts
      elif [ "${PACKAGE_FROZEN}" = 'true' ]; then
        pnpm install --ignore-workspace --frozen-lockfile
      elif [ "${PACKAGE_IGNORE_SCRIPTS}" = 'true' ]; then
        pnpm install --ignore-workspace --ignore-scripts
      else
        pnpm install --ignore-workspace
      fi
      ;;
    yarn)
      if [ "${PACKAGE_IGNORE_SCRIPTS}" = 'true' ]; then
        yarn_version="$(yarn --version)"
        yarn_major="${yarn_version%%.*}"

        if [ "${PACKAGE_FROZEN}" = 'true' ] && [ "${yarn_major}" -ge 2 ] 2>/dev/null; then
          YARN_ENABLE_SCRIPTS=false yarn install --frozen-lockfile
        elif [ "${PACKAGE_FROZEN}" = 'true' ]; then
          yarn install --frozen-lockfile --ignore-scripts
        elif [ "${yarn_major}" -ge 2 ] 2>/dev/null; then
          YARN_ENABLE_SCRIPTS=false yarn install
        else
          yarn install --ignore-scripts
        fi
      elif [ "${PACKAGE_FROZEN}" = 'true' ]; then
        yarn install --frozen-lockfile
      else
        yarn install
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
