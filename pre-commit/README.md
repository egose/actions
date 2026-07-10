# Run and Handle Pre-Commit

Runs `pre-commit` for the repository, optionally commits any hook-generated changes, and fails the job when changes are left uncommitted.

`egose/actions/precommit@main` remains available as a compatibility wrapper, but new usage should prefer `egose/actions/pre-commit@main`.

## What It Does

- Restores the `~/.cache/pre-commit` cache.
- Reuses existing `python3` and `pre-commit`, or installs missing dependencies automatically.
- Runs `pre-commit run --all-files` against the configured file.
- Detects whether hooks changed tracked files.
- Optionally commits and pushes those changes on `pull_request` and/or `push` events.
- Fails the workflow if changes were made but automatic commits are disabled.

## Usage

### Basic

```yaml
name: Pre-Commit

on:
  pull_request:
  push:

jobs:
  pre-commit:
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Run pre-commit action
        uses: egose/actions/pre-commit@main
```

### Disable Auto-Commit on Push

```yaml
- name: Run pre-commit without push auto-commit
  uses: egose/actions/pre-commit@main
  with:
    commit-on-pr: 'true'
    commit-on-push: 'false'
```

### Use a Custom Config File

```yaml
- name: Run pre-commit with custom config
  uses: egose/actions/pre-commit@main
  with:
    config: .github/pre-commit-config.yaml
```

### Pin Fallback Dependency Versions

```yaml
- name: Run pre-commit with pinned fallback tool versions
  uses: egose/actions/pre-commit@main
  with:
    python-version: '3.14.6'
    pre-commit-version: '4.6.0'
```

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `config` | No | `.pre-commit-config.yaml` | Path to the pre-commit configuration file. |
| `python-version` | No | `3.14.6` | Python version to install with `asdf` when `python3` is missing. |
| `pre-commit-version` | No | `4.6.0` | `pre-commit` version to install when `pre-commit` is missing. |
| `commit-on-pr` | No | `"true"` | Commit and push hook changes when the workflow runs on `pull_request`. |
| `commit-on-push` | No | `"false"` | Commit and push hook changes when the workflow runs on `push`. |

## Notes

- If `python3` is missing, the action installs `asdf` and Python automatically before running hooks.
- If `pre-commit` is missing, the action installs the configured version automatically with `pip --user`.
- Existing `python3` and `pre-commit` installations are reused as-is.
- Automatic push-back requires repository write permissions and a checkout that can push to the current branch.
- On pull requests from forks, the push step may not be allowed by repository permissions or token restrictions.
- When automatic commit is disabled for the current event, the action fails intentionally if hooks modified files.
