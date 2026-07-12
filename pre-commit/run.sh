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
else
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
fi

pre-commit --version

config_file="${PRECOMMIT_CONFIG}"

if [ -f "$config_file" ]; then
  need_py=false
  python3 -c "import yaml" 2>/dev/null || need_py=true
  if [ "$need_py" = "true" ]; then
    python3 -m pip install --quiet --user pyyaml
  fi
  python3 - "$config_file" <<'PY'
import sys, os, stat, yaml
with open(sys.argv[1]) as f:
    cfg = yaml.safe_load(f) or {}
for repo in cfg.get("repos", []):
    if repo.get("repo") == "local":
        for hook in repo.get("hooks", []):
            entry = hook.get("entry")
            if entry and os.path.isfile(entry):
                os.chmod(entry, os.stat(entry).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
                print(f"chmod +x {entry}")
PY
fi

pre_commit_exit_code=0
pre-commit run --config="$config_file" --color=always --show-diff-on-failure --all-files || pre_commit_exit_code=$?

made_changes=false
if ! git diff --exit-code; then
  made_changes=true
  echo "Pre-commit made changes, committing and pushing..."
else
  echo "No pre-commit changes detected."
fi

event_name="${GITHUB_EVENT_NAME:-}"
commit_on_pr="${PRECOMMIT_COMMIT_ON_PR:-false}"
commit_on_push="${PRECOMMIT_COMMIT_ON_PUSH:-false}"

allow_commit=false
if [ "$event_name" = "pull_request" ] && [ "$commit_on_pr" = "true" ]; then
  allow_commit=true
elif [ "$event_name" = "push" ] && [ "$commit_on_push" = "true" ]; then
  allow_commit=true
fi

if [ "$made_changes" = "true" ] && [ "$allow_commit" = "true" ]; then
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  head_ref="${GITHUB_HEAD_REF:-}"
  if [ -z "$head_ref" ]; then
    head_ref="${GITHUB_REF_NAME:-}"
  fi
  git checkout "$head_ref"
  git add -u
  git commit -m "chore(pre-commit): apply automatic formatting and linting fixes"
  git push origin "$head_ref"

  pre-commit run --config="$config_file" --color=always --show-diff-on-failure --all-files
elif [ "$made_changes" = "true" ] && [ "$allow_commit" != "true" ]; then
  echo "❌ Pre-commit made changes, but automatic commits are disabled for this event."
  echo "Please run 'pre-commit run --all-files' locally and commit the changes."
  exit 1
fi

if [ "$pre_commit_exit_code" != "0" ] && [ "$made_changes" != "true" ]; then
  echo "❌ Pre-commit hooks failed."
  exit 1
fi
