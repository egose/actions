# Install Packages with NPM

Installs dependencies with npm for one or more directories that contain a `package.json` file.

## What It Does

- Restores a cache for `**/node_modules` keyed by all `package-lock.json` files.
- Iterates through the configured directories.
- Runs `npm install` in each existing directory.
- Optionally runs `npm ci` for strict CI installs.
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
          node-version: '26'

      - name: Install dependencies
        uses: egose/actions/npm-packages@main
```

### Install Multiple Workspaces

```yaml
- name: Install multiple package sets
  uses: egose/actions/npm-packages@main
  with:
    paths: |
      .
      apps/web
      packages/shared
```

### Strict Lockfile Mode

```yaml
- name: Install dependencies from lockfiles only
  uses: egose/actions/npm-packages@main
  with:
    frozen: 'true'
```

### Skip Lifecycle Scripts

```yaml
- name: Install dependencies without lifecycle scripts
  uses: egose/actions/npm-packages@main
  with:
    ignore-scripts: 'true'
```

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `paths` | No | `.` | Newline-separated list of directories that contain `package.json` files. |
| `frozen` | No | `'false'` | Runs `npm ci` instead of `npm install`. |
| `ignore-scripts` | No | `'false'` | Adds `--ignore-scripts` to the npm install command. |

## Notes

- This action does not install Node.js. Set it up earlier in the workflow.
- Missing directories are skipped.
- The cache key is based on `hashFiles('**/package-lock.json')`, so any lockfile change refreshes the cache.
- `frozen: 'true'` requires matching `package-lock.json` files to already exist for each target directory.
- `ignore-scripts: 'true'` applies to both normal installs and frozen installs.
- This action has no outputs.
