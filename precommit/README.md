# Run and Handle Pre-Commit

Runs `pre-commit` for the repository, optionally commits any hook-generated changes, and fails the job when changes are left uncommitted.

## What It Does

- Restores the `~/.cache/pre-commit` cache.
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
  precommit:
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install pre-commit
        run: pip install pre-commit

      - name: Run pre-commit action
        uses: egose/actions/precommit@main
```

### Disable Auto-Commit on Push

```yaml
- name: Run pre-commit without push auto-commit
  uses: egose/actions/precommit@main
  with:
    commit-on-pr: 'true'
    commit-on-push: 'false'
```

### Use a Custom Config File

```yaml
- name: Run pre-commit with custom config
  uses: egose/actions/precommit@main
  with:
    config: .github/pre-commit-config.yaml
```

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `config` | No | `.pre-commit-config.yaml` | Path to the pre-commit configuration file. |
| `commit-on-pr` | No | `"true"` | Commit and push hook changes when the workflow runs on `pull_request`. |
| `commit-on-push` | No | `"false"` | Commit and push hook changes when the workflow runs on `push`. |

## Notes

- This action does not install `pre-commit`; your workflow must do that before calling it.
- Automatic push-back requires repository write permissions and a checkout that can push to the current branch.
- On pull requests from forks, the push step may not be allowed by repository permissions or token restrictions.
- When automatic commit is disabled for the current event, the action fails intentionally if hooks modified files.
