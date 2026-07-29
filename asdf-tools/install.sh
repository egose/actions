#!/usr/bin/env bash

set -euo pipefail

is_truthy() {
  case "${1:-}" in
    true|TRUE|True|1|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

asdf --version
cd "$ASDF_TOOLS_CONTEXT"

echo "✅ Adding additional plugins..."
while IFS= read -r plugin; do
  if [[ -z "$plugin" ]]; then
    continue
  fi

  key=${plugin%%=*}
  url=${plugin#*=}
  if [[ "$key" == "$url" ]]; then
    continue
  fi

  echo "➡️ $key $url..."
  asdf plugin add "$key" "$url" || true
done <<< "$ASDF_EXTRA_PLUGINS"

echo "✅ Adding main plugins..."
while IFS= read -r line; do
  if [[ -z "$line" || "$line" =~ ^# ]]; then
    continue
  fi

  tool="${line%% *}"
  asdf plugin add "$tool" || true
done < .tool-versions

if is_truthy "${ASDF_UPDATE_PLUGINS:-false}"; then
  asdf plugin update --all
fi

asdf plugin list --urls --refs

echo "✅ Installing tools..."
while IFS= read -r line; do
  # Skip empty lines or lines starting with comments (#)
  if [[ -n "$line" && ! "$line" =~ ^# ]]; then
    tool=$(echo "$line" | awk '{print $1}')
    version=$(echo "$line" | awk '{print $2}')

    echo "➡️ $tool $version..."
    asdf install "$tool" "$version"
    asdf reshim "$tool"
  fi
done < .tool-versions

asdf reshim
asdf install
echo "🚀 tools installed successfully"
