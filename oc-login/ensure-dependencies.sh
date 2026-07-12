#!/usr/bin/env bash

set -euo pipefail

if command -v oc >/dev/null 2>&1; then
  echo "✅ oc already available"
  exit 0
fi

echo "➡️ Installing asdf ${OCLOGIN_ASDF_VERSION}..."
ASDF_VERSION="${OCLOGIN_ASDF_VERSION}" bash "${OCLOGIN_ACTION_PATH}/../asdf-install/install.sh"
export PATH="${RUNNER_TEMP}/asdf-bin:${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"

if ! command -v asdf >/dev/null 2>&1; then
  echo "❌ asdf is unavailable after bootstrap"
  exit 1
fi

echo "➡️ Installing oc ${OCLOGIN_OC_VERSION}..."
asdf plugin add oc https://github.com/sqtran/asdf-oc.git || true
asdf install oc "${OCLOGIN_OC_VERSION}"

oc_root=""
if oc_root="$(asdf where oc "${OCLOGIN_OC_VERSION}" 2>/dev/null)"; then
  :
else
  installed_version="$(asdf list oc | awk 'NF { version=$1 } END { gsub(/^[* ]+/, "", version); print version }')"
  if [ -z "$installed_version" ]; then
    echo "❌ Unable to determine installed oc version"
    exit 1
  fi

  oc_root="$(asdf where oc "$installed_version")"
fi

echo "$oc_root/bin" >> "$GITHUB_PATH"
export PATH="$oc_root/bin:$PATH"

if ! command -v oc >/dev/null 2>&1; then
  echo "❌ oc is unavailable after dependency bootstrap"
  exit 1
fi

oc version --client || oc version
