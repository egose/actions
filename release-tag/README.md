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
```

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `tag` | No | `""` | Explicit semantic version such as `1.2.3`. |
| `github-token` | Yes |  | Token used to create the PR, add labels, and optionally merge and delete the branch. |
| `auto-merge-pr` | No | `"false"` | Merges the generated release PR immediately after creation when set to `true`. |
| `delete-merged-branch` | No | `"false"` | Deletes the generated `changelog/*` branch after a successful auto-merge. |
| `release-it-path` | No | `./node_modules/.bin/release-it` | Path to the `release-it` executable. |

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

## Troubleshooting

- If no previous tag exists, provide `tag` once to seed release history.
- If PR creation or merge fails, verify repository permissions and token scopes first.
