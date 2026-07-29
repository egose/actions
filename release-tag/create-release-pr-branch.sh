#!/usr/bin/env bash

set -euo pipefail

configure_gpg_signing() {
  mkdir -p "$HOME/.gnupg"
  chmod 700 "$HOME/.gnupg"
  printf 'pinentry-mode loopback\n' >> "$HOME/.gnupg/gpg.conf"
  printf 'allow-loopback-pinentry\n' >> "$HOME/.gnupg/gpg-agent.conf"

  if [ -n "${GPG_PRIVATE_KEY:-}" ]; then
    key_file="$(mktemp)"
    printf '%s' "$GPG_PRIVATE_KEY" > "$key_file"

    if [ -n "${GPG_PASSPHRASE:-}" ]; then
      gpg --batch --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" --import "$key_file"
    else
      gpg --batch --import "$key_file"
    fi

    rm -f "$key_file"
  fi

  signing_key="$(gpg --list-secret-keys --with-colons --fingerprint | grep '^fpr:' | head -n 1 | cut -d: -f10)"
  if [ -z "$signing_key" ]; then
    echo '::error::sign-commit is enabled but no GPG secret key is available. Provide gpg-private-key or import a key before running this action.'
    exit 1
  fi

  git config user.signingkey "$signing_key"
  git config commit.gpgsign true

  if [ -n "${GPG_PASSPHRASE:-}" ]; then
    gpg_wrapper="$(mktemp)"
    printf '%s\n' '#!/usr/bin/env bash' 'exec gpg --batch --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" "$@"' > "$gpg_wrapper"
    chmod 700 "$gpg_wrapper"
    export GPG_PASSPHRASE
    git config gpg.program "$gpg_wrapper"
  fi

  gpgconf --kill gpg-agent || true
}

write_multiline_output() {
  local key="$1"
  local value="$2"
  local delimiter

  delimiter="$(dd if=/dev/urandom bs=15 count=1 status=none | base64)"
  {
    echo "${key}<<${delimiter}"
    echo "$value"
    echo "$delimiter"
  } >> "$GITHUB_OUTPUT"
}

tag_version="v${RELEASE_TAG_VERSION:?RELEASE_TAG_VERSION is required}"
branch="changelog/${RELEASE_TAG_VERSION}"
base_branch="${RELEASE_BASE_BRANCH:?RELEASE_BASE_BRANCH is required}"

git config user.name "${GIT_USER_NAME:?GIT_USER_NAME is required}"
git config user.email "${GIT_USER_EMAIL:?GIT_USER_EMAIL is required}"

if [ "${SIGN_COMMIT:-false}" = 'true' ]; then
  configure_gpg_signing
fi

git push origin --delete "$branch" || true
git branch -D "$branch" || true
git checkout -b "$branch"
git push --set-upstream origin "$branch"

release_it_args=("${RELEASE_TAG_VERSION}" --ci)
if [ "${SIGN_COMMIT:-false}" = 'true' ]; then
  release_it_args+=(--git.commitArgs=--gpg-sign)
fi

"${RELEASE_IT_PATH:?RELEASE_IT_PATH is required}" "${release_it_args[@]}"
git push origin "$branch"

pr_title="chore(release): release candidate ${tag_version}"
pr_body="$(git tag -l --format='%(contents)' "$tag_version")"

echo "head_branch=${branch}" >> "$GITHUB_OUTPUT"
echo "base_branch=${base_branch}" >> "$GITHUB_OUTPUT"
echo "version=${tag_version}" >> "$GITHUB_OUTPUT"
echo "pr_title=${pr_title}" >> "$GITHUB_OUTPUT"
write_multiline_output "pr_body" "$pr_body"
