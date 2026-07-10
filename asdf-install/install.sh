#!/usr/bin/env bash

set -e

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
install_dir="${RUNNER_TEMP}/asdf-bin"

mkdir -p "$install_dir"
curl -fsSL -o asdf.tar.gz "$asdf_url" || { echo "❌ Failed to download ASDF from $asdf_url"; exit 1; }
tar -xzf asdf.tar.gz && rm -f asdf.tar.gz
install -m 0755 asdf "$install_dir/asdf"
rm -f asdf

echo "$install_dir" >> "$GITHUB_PATH"
echo "${ASDF_DATA_DIR:-$HOME/.asdf}/shims" >> "$GITHUB_PATH"
export PATH="$install_dir:${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"

echo "🚀 asdf installed successfully"
