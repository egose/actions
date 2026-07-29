#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
workspace="$(mktemp -d)"

cleanup() {
  rm -rf "$workspace"
}

trap cleanup EXIT

setup_git_repo() {
  local repo_dir="$1"

  git init --initial-branch=main "$repo_dir" >/dev/null
  git -C "$repo_dir" config user.name "Test User"
  git -C "$repo_dir" config user.email "test@example.com"
}

create_commit() {
  local repo_dir="$1"
  local message="$2"
  local body="${3:-}"
  local file_name="${4:-entry.txt}"

  printf '%s\n' "$message${body:+\n\n$body}" > "$repo_dir/${file_name}"
  git -C "$repo_dir" add "$file_name"

  if [ -n "$body" ]; then
    git -C "$repo_dir" commit -m "$message" -m "$body" >/dev/null
  else
    git -C "$repo_dir" commit -m "$message" >/dev/null
  fi
}

read_output_value() {
  local file_path="$1"
  local key="$2"

  grep "^${key}=" "$file_path" | cut -d= -f2-
}

read_multiline_output() {
  local file_path="$1"
  local key="$2"

  awk -v key="$key" '
    index($0, key "<<") == 1 {
      delimiter = substr($0, length(key) + 3)
      capture = 1
      next
    }
    capture && $0 == delimiter {
      exit
    }
    capture {
      print
    }
  ' "$file_path"
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" != "$actual" ]; then
    echo "$message"
    echo "expected: $expected"
    echo "actual:   $actual"
    exit 1
  fi
}

test_determine_tag_from_input() {
  local repo_dir="$workspace/determine-input"
  local output_file="$workspace/determine-input.out"

  setup_git_repo "$repo_dir"
  create_commit "$repo_dir" "chore: initial"

  (
    cd "$repo_dir"
    GITHUB_OUTPUT="$output_file" \
    RELEASE_TAG_INPUT='2.4.6' \
    bash "$repo_root/release-tag/determine-tag.sh"
  )

  assert_equals '2.4.6' "$(read_output_value "$output_file" tag)" 'determine-tag should respect explicit input'
}

test_determine_tag_patch_bump() {
  local repo_dir="$workspace/determine-patch"
  local output_file="$workspace/determine-patch.out"

  setup_git_repo "$repo_dir"
  create_commit "$repo_dir" "chore: initial"
  git -C "$repo_dir" tag -a v1.2.3 -m 'Release v1.2.3' >/dev/null
  create_commit "$repo_dir" "chore: maintenance" '' 'patch.txt'

  (
    cd "$repo_dir"
    GITHUB_OUTPUT="$output_file" \
    RELEASE_TAG_INPUT='' \
    bash "$repo_root/release-tag/determine-tag.sh"
  )

  assert_equals '1.2.4' "$(read_output_value "$output_file" tag)" 'determine-tag should bump patch for non-feat commits'
}

test_determine_tag_minor_bump() {
  local repo_dir="$workspace/determine-minor"
  local output_file="$workspace/determine-minor.out"

  setup_git_repo "$repo_dir"
  create_commit "$repo_dir" "chore: initial"
  git -C "$repo_dir" tag -a v1.2.3 -m 'Release v1.2.3' >/dev/null
  create_commit "$repo_dir" "feat: add reporting" '' 'minor.txt'

  (
    cd "$repo_dir"
    GITHUB_OUTPUT="$output_file" \
    RELEASE_TAG_INPUT='' \
    bash "$repo_root/release-tag/determine-tag.sh"
  )

  assert_equals '1.3.0' "$(read_output_value "$output_file" tag)" 'determine-tag should bump minor for feat commits'
}

test_determine_tag_major_bump() {
  local repo_dir="$workspace/determine-major"
  local output_file="$workspace/determine-major.out"

  setup_git_repo "$repo_dir"
  create_commit "$repo_dir" "chore: initial"
  git -C "$repo_dir" tag -a v1.2.3 -m 'Release v1.2.3' >/dev/null
  create_commit "$repo_dir" "feat: replace api" 'BREAKING CHANGE: old API removed' 'major.txt'

  (
    cd "$repo_dir"
    GITHUB_OUTPUT="$output_file" \
    RELEASE_TAG_INPUT='' \
    bash "$repo_root/release-tag/determine-tag.sh"
  )

  assert_equals '2.0.0' "$(read_output_value "$output_file" tag)" 'determine-tag should bump major for breaking changes'
}

test_create_release_pr_branch() {
  local remote_dir="$workspace/release-remote.git"
  local repo_dir="$workspace/release-work"
  local fake_release_it="$workspace/fake-release-it.sh"
  local output_file="$workspace/create-release.out"
  local remote_head
  local local_head
  local pr_body

  git init --bare --initial-branch=main "$remote_dir" >/dev/null
  git clone "$remote_dir" "$repo_dir" >/dev/null 2>&1
  git -C "$repo_dir" config user.name "Test User"
  git -C "$repo_dir" config user.email "test@example.com"
  create_commit "$repo_dir" "chore: initial"
  git -C "$repo_dir" push --set-upstream origin main >/dev/null 2>&1
  git -C "$repo_dir" checkout -b changelog/1.2.4 >/dev/null 2>&1
  git -C "$repo_dir" push --set-upstream origin changelog/1.2.4 >/dev/null 2>&1
  git -C "$repo_dir" checkout main >/dev/null 2>&1

  cat > "$fake_release_it" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

version="$1"
shift

printf 'release %s\n' "$version" > RELEASE_NOTES.txt
git add RELEASE_NOTES.txt
git commit -m "chore(release): ${version}" >/dev/null
git tag -a "v${version}" -m $'Line one\nLine two with `${danger}`'
EOF
  chmod 755 "$fake_release_it"

  (
    cd "$repo_dir"
    GITHUB_OUTPUT="$output_file" \
    RELEASE_TAG_VERSION='1.2.4' \
    RELEASE_BASE_BRANCH='main' \
    RELEASE_IT_PATH="$fake_release_it" \
    GIT_USER_NAME='Release Bot' \
    GIT_USER_EMAIL='release@example.com' \
    SIGN_COMMIT='false' \
    bash "$repo_root/release-tag/create-release-pr-branch.sh"
  )

  remote_head="$(git --git-dir "$remote_dir" rev-parse refs/heads/changelog/1.2.4)"
  local_head="$(git -C "$repo_dir" rev-parse HEAD)"
  assert_equals "$local_head" "$remote_head" 'release branch should be pushed to origin'

  assert_equals 'changelog/1.2.4' "$(read_output_value "$output_file" head_branch)" 'head_branch output mismatch'
  assert_equals 'main' "$(read_output_value "$output_file" base_branch)" 'base_branch output mismatch'
  assert_equals 'v1.2.4' "$(read_output_value "$output_file" version)" 'version output mismatch'
  assert_equals 'chore(release): release candidate v1.2.4' "$(read_output_value "$output_file" pr_title)" 'pr_title output mismatch'

  pr_body="$(read_multiline_output "$output_file" pr_body)"
  assert_equals $'Line one\nLine two with `${danger}`' "$pr_body" 'pr_body output mismatch'

  test -n "$(git -C "$repo_dir" tag -l 'v1.2.4')"
}

test_determine_tag_from_input
test_determine_tag_patch_bump
test_determine_tag_minor_bump
test_determine_tag_major_bump
test_create_release_pr_branch

printf 'release-tag shell tests passed\n'
