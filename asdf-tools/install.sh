#!/usr/bin/env bash

set -e

asdf --version
echo "$PATH"
echo "$ASDF_TOOLS_CONTEXT"
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
cat .tool-versions | cut -f 1 -d ' ' | xargs -n 1 asdf plugin add || true
asdf plugin update --all
asdf plugin list --urls --refs

echo "✅ Installing tools..."
while read -r line; do
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
