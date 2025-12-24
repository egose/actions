# Create Release Tag Action

A composite GitHub Action that automates the release process. It determines the next semantic version based on **Conventional Commits**, generates a changelog using `release-it`, and opens a Pull Request for the release candidate.

## 🚀 Features

- **Auto-Versioning:** Automatically calculates the next version (patch, minor, or major) based on commit history.
- **Manual Override:** Allows users to manually specify a version via workflow inputs.
- **Changelog Generation:** Integrates with `release-it` to maintain an updated `CHANGELOG.md`.
- **Release Candidate PRs:** Instead of pushing directly to main, it creates a PR with the changelog for team review.
- **Automated Labeling:** Labels the resulting PR with `release-candidate` and the version number.

---

## 📥 Usage

To use this action, ensure your repository is configured for [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

### Prerequisites

1. **Release-it:** Your project must have `release-it` installed as a dev dependency.
2. **Permissions:** The `GITHUB_TOKEN` used must have `write` permissions for contents, issues, and pull-requests.

### Example Workflow

Create a file at `.github/workflows/release.yml`:

```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      tag:
        description: "Manual Version (optional)"
        required: false

jobs:
  create-release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write

    steps:
      - name: Create Release Tag
        uses: egose/actions/release-tag@main
        with:
          tag: ${{ github.event.inputs.tag }}
          ssh-key: ${{ secrets.RELEASE_SSH_KEY }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

---

## ⚙️ Configuration

### Inputs

| Input          | Description                                                                                | Required | Default        |
| -------------- | ------------------------------------------------------------------------------------------ | -------- | -------------- |
| `tag`          | Manually specify a version (e.g., `1.2.3`). If empty, it auto-determines based on commits. | No       | `""`           |
| `ssh-key`      | SSH Private Key used to push the tag and changelog branch.                                 | **Yes**  | N/A            |
| `github-token` | The `GITHUB_TOKEN` or a PAT to create the Pull Request.                                    | **Yes**  | `github.token` |

---

## 🛠 How it Works

1. **Validation:** Ensures the action is running on a branch (not a detached tag).
2. **Detection:** \* If a `tag` input is provided, it validates the SemVer format.

- If no input is provided, it fetches the latest tag and analyzes the commit messages since that tag to decide the bump type.

3. **Branching:** Creates a temporary branch named `changelog/X.Y.Z`.
4. **Release-it:** Executes `./node_modules/.bin/release-it` to update the changelog and create a local tag.
5. **PR Creation:** Opens a PR back to the base branch containing the new changelog entries in the PR body.

---

## 📝 Troubleshooting

- **No previous tag found:** If this is your first release, you must provide a manual tag via the `tag` input once to seed the versioning history.
- **Permission Denied:** Ensure your `ssh-key` has write access to the repository and that the GitHub Action permissions in Settings allow for PR creation.
