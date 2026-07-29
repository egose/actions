#!/usr/bin/env bash

set -euo pipefail

next_version=""
input_tag="${RELEASE_TAG_INPUT:-}"

if [ -n "$input_tag" ]; then
  if ! printf '%s' "$input_tag" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "::error::Provided tag '$input_tag' does not follow semantic versioning"
    exit 1
  fi

  next_version="${input_tag//v}"
else
  last_tag="$(git describe --tags --abbrev=0 2>/dev/null || true)"
  if [ -z "$last_tag" ]; then
    echo "::error::No previous tag found and no tag input provided."
    exit 1
  fi

  if ! [[ "$last_tag" =~ v([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    echo "::error::Last tag '$last_tag' does not follow 'vX.Y.Z' format."
    exit 1
  fi

  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  patch="${BASH_REMATCH[3]}"
  commit_messages="$(git log "${last_tag}..HEAD" --pretty=format:%B)"

  if printf '%s' "$commit_messages" | grep -qE '(BREAKING CHANGE:|^feat\([^)]*\)!:|^fix\([^)]*\)!:|!:)' ; then
    bump="major"
  elif printf '%s' "$commit_messages" | grep -qE '^feat(\(.+\))?:'; then
    bump="minor"
  else
    bump="patch"
  fi

  case "$bump" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
  esac

  next_version="${major}.${minor}.${patch}"
fi

echo "tag=${next_version}" >> "$GITHUB_OUTPUT"
