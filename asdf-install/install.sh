#!/usr/bin/env bash

set -euo pipefail

compute_sha256() {
  local file_path="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file_path" | awk '{print $1}'
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
    return
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file_path" | awk '{print $NF}'
    return
  fi

  echo "❌ No SHA-256 tool available (expected sha256sum, shasum, or openssl)"
  exit 1
}

ASDF_VERSION="${ASDF_VERSION:-v0.20.0}"
install_dir="${RUNNER_TEMP}/asdf-bin"
shims_dir="${ASDF_DATA_DIR:-$HOME/.asdf}/shims"
work_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$work_dir"
}

trap cleanup EXIT

if [ -x "$install_dir/asdf" ]; then
  current_version="$($install_dir/asdf --version 2>/dev/null || true)"

  if [[ "$current_version" == *"${ASDF_VERSION}"* ]]; then
    echo "$install_dir" >> "$GITHUB_PATH"
    echo "$shims_dir" >> "$GITHUB_PATH"
    export PATH="$install_dir:$shims_dir:$PATH"

    echo "✅ asdf ${ASDF_VERSION} restored from cache"
    exit 0
  fi

  echo "➡️ Cached asdf version mismatch (${current_version}), installing ${ASDF_VERSION}..."
fi

if command -v asdf >/dev/null 2>&1; then
  current_version="$(asdf --version 2>/dev/null || true)"

  if [[ "$current_version" == *"${ASDF_VERSION}"* ]]; then
    existing_dir="$(dirname "$(command -v asdf)")"

    echo "$existing_dir" >> "$GITHUB_PATH"
    echo "$shims_dir" >> "$GITHUB_PATH"
    export PATH="$existing_dir:$shims_dir:$PATH"

    echo "✅ asdf ${ASDF_VERSION} already available"
    exit 0
  fi

  echo "➡️ asdf version mismatch (${current_version}), installing ${ASDF_VERSION}..."
fi

case "$(uname -s)" in
  Linux) asdf_os=linux ;;
  Darwin) asdf_os=darwin ;;
  *)
    echo "❌ Unsupported OS: $(uname -s)"
    exit 1
    ;;
esac

case "$(uname -m)" in
  x86_64) asdf_arch=amd64 ;;
  arm64|aarch64) asdf_arch=arm64 ;;
  *)
    echo "❌ Unsupported architecture: $(uname -m)"
    exit 1
    ;;
esac

asdf_asset="asdf-${ASDF_VERSION}-${asdf_os}-${asdf_arch}.tar.gz"
asdf_url="https://github.com/asdf-vm/asdf/releases/download/${ASDF_VERSION}/${asdf_asset}"
asdf_release_metadata_url="https://api.github.com/repos/asdf-vm/asdf/releases/tags/${ASDF_VERSION}"
asdf_release_metadata_file="${work_dir}/asdf-release.json"
asdf_archive="${work_dir}/${asdf_asset}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ python3 is required to verify the asdf release checksum"
  exit 1
fi

asdf_release_metadata_attempts=3
for ((attempt = 1; attempt <= asdf_release_metadata_attempts; attempt++)); do
  if curl -fsSL -H "Accept: application/vnd.github+json" -o "$asdf_release_metadata_file" "$asdf_release_metadata_url"; then
    break
  fi

  if ((attempt == asdf_release_metadata_attempts)); then
    echo "❌ Failed to download ASDF release metadata from $asdf_release_metadata_url"
    exit 1
  fi

  echo "⚠️ Failed to download ASDF release metadata, retrying..."
  sleep 2
done

expected_sha256="$(ASDF_ASSET="$asdf_asset" python3 - "$asdf_release_metadata_file" <<'PY'
import json
import os
import sys
from pathlib import Path

asset_name = os.environ["ASDF_ASSET"]
metadata = json.loads(Path(sys.argv[1]).read_text())

for asset in metadata.get("assets", []):
    if asset.get("name") != asset_name:
        continue

    digest = asset.get("digest", "")
    if not digest.startswith("sha256:"):
        break

    print(digest.split(":", 1)[1])
    sys.exit(0)

sys.exit(1)
PY
)" || {
  echo "❌ Failed to determine the expected SHA-256 checksum for $asdf_asset"
  exit 1
}

mkdir -p "$install_dir"
curl -fsSL -o "$asdf_archive" "$asdf_url" || { echo "❌ Failed to download ASDF from $asdf_url"; exit 1; }

actual_sha256="$(compute_sha256 "$asdf_archive")"
if [ "$actual_sha256" != "$expected_sha256" ]; then
  echo "❌ ASDF checksum mismatch for $asdf_asset"
  echo "Expected: $expected_sha256"
  echo "Actual:   $actual_sha256"
  exit 1
fi

tar -xzf "$asdf_archive" -C "$work_dir"
install -m 0755 "$work_dir/asdf" "$install_dir/asdf"

echo "$install_dir" >> "$GITHUB_PATH"
echo "$shims_dir" >> "$GITHUB_PATH"
export PATH="$install_dir:$shims_dir:$PATH"

echo "🚀 asdf installed successfully"
