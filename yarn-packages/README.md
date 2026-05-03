# Install Packages with Yarn

Installs dependencies with Yarn for one or more directories that contain a `package.json` file.

## What It Does

- Restores a cache for `**/node_modules` keyed by all `yarn.lock` files.
- Iterates through the configured directories.
- Runs `yarn install` in each existing directory.

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

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `paths` | No | `.` | Newline-separated list of directories that contain `package.json` files. |

## Notes

- This action does not install Node.js or Yarn. Set those up earlier in the workflow.
- Missing directories are skipped.
- The cache key is based on `hashFiles('**/yarn.lock')`, so any lockfile change refreshes the cache.
- This action has no outputs.
