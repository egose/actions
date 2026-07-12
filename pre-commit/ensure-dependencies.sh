#!/usr/bin/env bash

set -euo pipefail

python_ready=false
precommit_ready=false

if command -v python3 >/dev/null 2>&1; then
  python_ready=true
fi

if command -v pre-commit >/dev/null 2>&1; then
  precommit_ready=true
fi

if [ "$python_ready" = "true" ] && [ "$precommit_ready" = "true" ]; then
  echo "✅ python3 and pre-commit already available"
  exit 0
fi

if [ "$python_ready" != "true" ]; then
  echo "➡️ Installing asdf ${PRECOMMIT_ASDF_VERSION} and Python ${PRECOMMIT_PYTHON_VERSION}..."
  ASDF_VERSION="${PRECOMMIT_ASDF_VERSION}" bash "${PRECOMMIT_ACTION_PATH}/../asdf-install/install.sh"
  export PATH="${RUNNER_TEMP}/asdf-bin:${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"

  if ! command -v asdf >/dev/null 2>&1; then
    echo "❌ asdf is unavailable after bootstrap"
    exit 1
  fi

  asdf plugin add python https://github.com/danhper/asdf-python.git || true
  asdf install python "${PRECOMMIT_PYTHON_VERSION}"

  python_root="$(asdf where python "${PRECOMMIT_PYTHON_VERSION}")"
  echo "$python_root/bin" >> "$GITHUB_PATH"
  export PATH="$python_root/bin:$PATH"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ python3 is unavailable after dependency bootstrap"
  exit 1
fi

if [ "$precommit_ready" != "true" ]; then
  echo "➡️ Installing pre-commit ${PRECOMMIT_VERSION}..."

  if ! python3 -m pip --version >/dev/null 2>&1; then
    python3 -m ensurepip --upgrade
  fi

  python3 -m pip install --user "pre-commit==${PRECOMMIT_VERSION}"

  user_base="$(python3 -m site --user-base)"
  echo "$user_base/bin" >> "$GITHUB_PATH"
  export PATH="$user_base/bin:$PATH"
fi

pre-commit --version
