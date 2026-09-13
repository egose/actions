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

asdf_release_metadata_attempts=5
github_token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
api_curl_args=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
if [ -n "$github_token" ]; then
  api_curl_args+=(-H "Authorization: Bearer ${github_token}")
else
  echo "⚠️ GITHUB_TOKEN/GH_TOKEN is not set; using unauthenticated GitHub API requests (60 req/h shared IP quota, prone to intermittent 403)..."
fi

asdf_release_headers_file="${work_dir}/asdf-release.headers"
for ((attempt = 1; attempt <= asdf_release_metadata_attempts; attempt++)); do
  http_code="000"
  http_code="$(curl -sSL -D "$asdf_release_headers_file" -o "$asdf_release_metadata_file" -w "%{http_code}" "${api_curl_args[@]}" "$asdf_release_metadata_url" 2>/dev/null || true)"
  if [ "$http_code" = "200" ]; then
    break
  fi

  rate_remaining="$(grep -i '^x-ratelimit-remaining:' "$asdf_release_headers_file" 2>/dev/null | awk '{print $2}' | tr -d '\r' || true)"
  rate_reset="$(grep -i '^x-ratelimit-reset:' "$asdf_release_headers_file" 2>/dev/null | awk '{print $2}' | tr -d '\r' || true)"
  retry_after="$(grep -i '^retry-after:' "$asdf_release_headers_file" 2>/dev/null | awk '{print $2}' | tr -d '\r' || true)"
  error_body="$(head -c 500 "$asdf_release_metadata_file" 2>/dev/null || true)"

  if ((attempt == asdf_release_metadata_attempts)); then
    echo "❌ Failed to download ASDF release metadata from $asdf_release_metadata_url (HTTP $http_code after $attempt attempts)"
    echo "Response headers:"
    grep -iE '^(http/|x-ratelimit-|retry-after|gh-)' "$asdf_release_headers_file" 2>/dev/null || true
    echo "Response body: $error_body"
    if [ "$http_code" = "403" ] || [ "$http_code" = "429" ]; then
      echo "ℹ️ 403/429 from api.github.com is almost always rate limiting: unauthenticated callers share 60 req/h per egress IP on hosted runners. Pass a token via the action's 'github-token' input (5,000 req/h) to fix it."
    fi
    exit 1
  fi

  sleep_seconds=0
  now_seconds="$(date +%s)"
  if [[ "$retry_after" =~ ^[0-9]+$ ]] && ((retry_after > 0)); then
    sleep_seconds=$((retry_after + 1))
    echo "⚠️ GitHub API returned HTTP $http_code (attempt $attempt/$asdf_release_metadata_attempts), honoring Retry-After: sleeping ${sleep_seconds}s..."
  elif [[ "$rate_remaining" == "0" && "$rate_reset" =~ ^[0-9]+$ ]]; then
    sleep_seconds=$((rate_reset - now_seconds + 5))
    if ((sleep_seconds < 5)); then
      sleep_seconds=5
    fi
    if ((sleep_seconds > 120)); then
      echo "❌ GitHub API rate limit exhausted (HTTP $http_code). Quota resets at $(date -u -d "@$rate_reset" 2>/dev/null || date -u -r "$rate_reset" 2>/dev/null || echo "$rate_reset"). Rerun later or use an authenticated token with remaining quota."
      exit 1
    fi
    echo "⚠️ GitHub API rate limit exhausted (attempt $attempt/$asdf_release_metadata_attempts), sleeping ${sleep_seconds}s until reset..."
  else
    sleep_seconds=$((2 ** attempt + RANDOM % 3))
    echo "⚠️ Failed to download ASDF release metadata (HTTP $http_code, attempt $attempt/$asdf_release_metadata_attempts), retrying in ${sleep_seconds}s... Body: $error_body"
  fi
  sleep "$sleep_seconds"
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
asdf_asset_attempts=5
asset_curl_args=(-fsSL)
if [ -n "$github_token" ]; then
  asset_curl_args+=(-H "Authorization: Bearer ${github_token}")
fi
for ((attempt = 1; attempt <= asdf_asset_attempts; attempt++)); do
  if curl "${asset_curl_args[@]}" -o "$asdf_archive" "$asdf_url"; then
    break
  fi

  if ((attempt == asdf_asset_attempts)); then
    echo "❌ Failed to download ASDF from $asdf_url"
    exit 1
  fi

  sleep_seconds=$((2 ** attempt + RANDOM % 3))
  echo "⚠️ Failed to download ASDF asset (attempt $attempt/$asdf_asset_attempts), retrying in ${sleep_seconds}s..."
  sleep "$sleep_seconds"
done

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
