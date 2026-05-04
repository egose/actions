# Create Release Tag

Determines the next semantic version, runs `release-it`, creates a release candidate pull request, and can optionally merge and clean up that PR automatically.

## What It Does

- Validates that the workflow is running on a branch.
- Uses a manual `tag` input or derives the next version from Conventional Commit messages since the latest tag.
- Creates a temporary `changelog/<version>` branch.
- Runs `release-it` to generate changelog and release changes.
- Opens a pull request back to the current branch and labels it.
- Optionally merges the PR and deletes the temporary branch.

## Prerequisites

- The repository should use [Conventional Commits](https://www.conventionalcommits.org/).
- `release-it` must already be available at `release-it-path`.
- The repository must be checked out with full history and tags.
- The token passed as `github-token` must be allowed to create pull requests. It also needs merge and branch-delete permissions when the optional automation flags are enabled.

## Usage

```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      tag:
        description: Manual version override
        required: false
      auto-merge-pr:
        description: Merge the generated PR automatically
        type: boolean
        required: false
        default: false
      delete-merged-branch:
        description: Delete the changelog branch after merge
        type: boolean
        required: false
        default: false

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          fetch-tags: true

      - name: Install dependencies
        run: yarn install --frozen-lockfile

      - name: Create release PR
        uses: egose/actions/release-tag@main
        with:
          tag: ${{ github.event.inputs.tag }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
          auto-merge-pr: ${{ github.event.inputs.auto-merge-pr }}
          delete-merged-branch: ${{ github.event.inputs.delete-merged-branch }}
          sign-commit: 'true'
          gpg-private-key: ${{ secrets.RELEASE_GPG_PRIVATE_KEY }}
          gpg-passphrase: ${{ secrets.RELEASE_GPG_PASSPHRASE }}
```

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `tag` | No | `""` | Explicit semantic version such as `1.2.3`. |
| `github-token` | Yes |  | Token used to create the PR, add labels, and optionally merge and delete the branch. |
| `auto-merge-pr` | No | `"false"` | Merges the generated release PR immediately after creation when set to `true`. |
| `delete-merged-branch` | No | `"false"` | Deletes the generated `changelog/*` branch after a successful auto-merge. |
| `release-it-path` | No | `./node_modules/.bin/release-it` | Path to the `release-it` executable. |
| `sign-commit` | No | `"false"` | Signs the release commit that `release-it` creates. |
| `gpg-private-key` | No | `""` | ASCII-armored GPG private key to import before creating the release commit. |
| `gpg-passphrase` | No | `""` | Passphrase for `gpg-private-key`, when the key is passphrase-protected. |

## How Versioning Works

- If `tag` is provided, that version is used directly after SemVer validation.
- If `tag` is not provided, the action reads the latest `vX.Y.Z` tag and inspects commit messages since that tag.
- Commits matching breaking-change patterns trigger a major bump.
- `feat:` commits trigger a minor bump.
- Everything else falls back to a patch bump.

## Notes

- The temporary branch name is `changelog/<version>`.
- The base branch is taken from `github.ref_name`, so the PR targets the branch that triggered the workflow.
- `delete-merged-branch` only runs after a successful auto-merge.
- If branch protection or required checks block merges, the auto-merge API call fails and the action fails with it.
- `sign-commit` does not create a new GPG key. It only tells the action to sign the `release-it` commit.
- When `sign-commit` is enabled, the action imports `gpg-private-key` if provided and then forces `release-it` to create its commit with `--gpg-sign`.
- If `gpg-private-key` is omitted, the runner must already have a usable GPG secret key before this action runs.
- `gpg-passphrase` is only needed when the signing key is passphrase-protected.
- This action currently sets the commit author to `github-actions[bot]`. That gives you a cryptographically signed commit, but GitHub may not show a green `Verified` badge unless the signing identity and uploaded public key match the author GitHub account.

## Generate a GPG Key for CI

Create a dedicated key pair for release automation on a trusted machine, then store the private key in your CI secrets.

1. Generate a key:

```sh
gpg --full-generate-key
```

Recommended answers:
- Key type: `RSA and RSA`
- Key size: `4096`
- Expiration: your team preference
- Real name: `Release Automation`
- Email: an address you control for this key
- Passphrase: set one unless you intentionally want an unprotected CI key

2. List the new key and copy its key ID or fingerprint:

```sh
gpg --list-secret-keys --keyid-format LONG
```

3. Export the private key in ASCII-armored format for `gpg-private-key`:

```sh
gpg --armor --export-secret-keys YOUR_KEY_ID
```

4. Save that exported block as a GitHub Actions secret, for example `RELEASE_GPG_PRIVATE_KEY`.

5. If the key has a passphrase, save that as another secret such as `RELEASE_GPG_PASSPHRASE`.

6. Optionally export the public key and add it to the GitHub account that owns the signing identity if you want GitHub signature verification:

```sh
gpg --armor --export YOUR_KEY_ID
```

Then upload that public key in GitHub under `Settings` -> `SSH and GPG keys` for the account that should own the signing key.

## CI Example

```yaml
- name: Create release PR
  uses: egose/actions/release-tag@main
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    sign-commit: 'true'
    gpg-private-key: ${{ secrets.RELEASE_GPG_PRIVATE_KEY }}
    gpg-passphrase: ${{ secrets.RELEASE_GPG_PASSPHRASE }}
```

## Troubleshooting

- If no previous tag exists, provide `tag` once to seed release history.
- If PR creation or merge fails, verify repository permissions and token scopes first.
- If commit signing fails, confirm the private key is ASCII-armored, the passphrase is correct, and at least one secret key is available to `gpg --list-secret-keys` on the runner.
