# Install Packages with Yarn

Installs dependencies with Yarn for one or more directories that contain a `package.json` file.

## What It Does

- Restores a cache for `**/node_modules` keyed by all `yarn.lock` files.
- Iterates through the configured directories.
- Runs `yarn install` in each existing directory.
- Optionally runs `yarn install --frozen-lockfile` for strict CI installs.
- Optionally skips lifecycle scripts using Yarn-version-aware behavior.

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
        uses: egose/actions/yarn-packages@main
```

### Install Multiple Workspaces

```yaml
- name: Install multiple package sets
  uses: egose/actions/yarn-packages@main
  with:
    paths: |
      .
      apps/web
      packages/shared
```

### Strict Lockfile Mode

```yaml
- name: Install dependencies from lockfiles only
  uses: egose/actions/yarn-packages@main
  with:
    frozen: 'true'
```

### Skip Lifecycle Scripts

```yaml
- name: Install dependencies without lifecycle scripts
  uses: egose/actions/yarn-packages@main
  with:
    ignore-scripts: 'true'
```

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `paths` | No | `.` | Newline-separated list of directories that contain `package.json` files. |
| `frozen` | No | `'false'` | Runs `yarn install --frozen-lockfile` instead of `yarn install`. |
| `ignore-scripts` | No | `'false'` | Skips lifecycle scripts. Uses `--ignore-scripts` for Yarn 1 and `YARN_ENABLE_SCRIPTS=false` for Yarn 2+. |

## Notes

- This action does not install Node.js or Yarn. Set those up earlier in the workflow.
- Missing directories are skipped.
- The cache key is based on `hashFiles('**/yarn.lock')`, so any lockfile change refreshes the cache.
- `frozen: 'true'` requires matching `yarn.lock` files to already exist for each target directory.
- `ignore-scripts: 'true'` checks the active Yarn major version in each target directory and chooses the compatible mechanism.
- This action has no outputs.
