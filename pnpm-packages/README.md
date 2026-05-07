# Install Packages with PNPM

Installs dependencies with pnpm for one or more directories that contain a `package.json` file.

## What It Does

- Restores a cache for `**/node_modules` keyed by all `pnpm-lock.yaml` files.
- Iterates through the configured directories.
- Runs `pnpm install` in each existing directory.
- Optionally runs `pnpm install --frozen-lockfile` for strict CI installs.
- Optionally adds `--ignore-scripts` to skip lifecycle scripts.

## Usage

### Basic

```yaml
name: Install Packages

on: push

jobs:
  dependencies:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - run: corepack enable

      - name: Install dependencies
        uses: egose/actions/pnpm-packages@main
```

### Install Multiple Workspaces

```yaml
- name: Install multiple package sets
  uses: egose/actions/pnpm-packages@main
  with:
    paths: |
      .
      apps/web
      packages/shared
```

### Strict Lockfile Mode

```yaml
- name: Install dependencies from lockfiles only
  uses: egose/actions/pnpm-packages@main
  with:
    frozen: 'true'
```

### Skip Lifecycle Scripts

```yaml
- name: Install dependencies without lifecycle scripts
  uses: egose/actions/pnpm-packages@main
  with:
    ignore-scripts: 'true'
```

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `paths` | No | `.` | Newline-separated list of directories that contain `package.json` files. |
| `frozen` | No | `'false'` | Runs `pnpm install --frozen-lockfile` instead of `pnpm install`. |
| `ignore-scripts` | No | `'false'` | Adds `--ignore-scripts` to the pnpm install command. |

## Notes

- This action does not install Node.js or pnpm. Set those up earlier in the workflow.
- Missing directories are skipped.
- The cache key is based on `hashFiles('**/pnpm-lock.yaml')`, so any lockfile change refreshes the cache.
- `frozen: 'true'` requires matching `pnpm-lock.yaml` files to already exist for each target directory.
- `ignore-scripts: 'true'` applies to both normal installs and frozen installs.
- This action has no outputs.
