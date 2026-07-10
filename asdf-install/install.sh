#!/usr/bin/env bash

set -e

ASDF_VERSION="${ASDF_VERSION:-v0.19.0}"
install_dir="${RUNNER_TEMP}/asdf-bin"
shims_dir="${ASDF_DATA_DIR:-$HOME/.asdf}/shims"

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

echo "🏠 $HOME"

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

mkdir -p "$install_dir"
curl -fsSL -o asdf.tar.gz "$asdf_url" || { echo "❌ Failed to download ASDF from $asdf_url"; exit 1; }
tar -xzf asdf.tar.gz && rm -f asdf.tar.gz
install -m 0755 asdf "$install_dir/asdf"
rm -f asdf

echo "$install_dir" >> "$GITHUB_PATH"
echo "$shims_dir" >> "$GITHUB_PATH"
export PATH="$install_dir:$shims_dir:$PATH"

echo "🚀 asdf installed successfully"
