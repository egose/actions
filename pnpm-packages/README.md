# Install Packages with PNPM

Installs dependencies with pnpm for one or more directories that contain a `package.json` file.

## What It Does

- Restores a cache for the pnpm store and the dlx cache, keyed by all `pnpm-lock.yaml` files and the `tools` input.
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
          node-version: '26'

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

### Cache Extra CLI Tools (Not in `package.json`)

Tools listed in `tools` are fetched with [`pnpm dlx`](https://pnpm.io/cli/dlx) so the dlx cache is warm for later steps. They are **not** added to any `package.json` or lockfile. Later steps run them with `pnpm dlx <tool> ...`, which then resolves instantly from the cache.

```yaml
- name: Install dependencies and cache tools
  uses: egose/actions/pnpm-packages@main
  with:
    tools: |
      turbo
      apps/web: vite prettier@3

- name: Run a cached tool
  run: pnpm dlx turbo build
```

Each line is either a space-separated list of packages (optionally pinned like `name@version`, or with a registry alias) run from the repository root, or prefixed with `path: ` to use a specific directory as the working directory.

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `paths` | No | `.` | Newline-separated list of directories that contain `package.json` files. |
| `frozen` | No | `'false'` | Runs `pnpm install --frozen-lockfile` instead of `pnpm install`. |
| `ignore-scripts` | No | `'false'` | Adds `--ignore-scripts` to the pnpm install command. |
| `tools` | No | `''` | Newline-separated CLI tools to pre-cache via `pnpm dlx`. Supports an optional `path:` prefix per line. |

## Notes

- This action does not install Node.js or pnpm. Set those up earlier in the workflow.
- Missing directories are skipped.
- The cache key is based on `hashFiles('**/pnpm-lock.yaml')`, so any lockfile change refreshes the cache.
- The pnpm dlx cache (`${XDG_CACHE_HOME:-~/.cache}/pnpm/dlx`) is cached alongside the pnpm store. A hash of the `tools` input is part of the cache key, so changing the tool set or its versions refreshes the cache.
- `frozen: 'true'` requires matching `pnpm-lock.yaml` files to already exist for each target directory.
- `ignore-scripts: 'true'` applies to both normal installs and frozen installs.
- Installs in a target directory that is itself a pnpm workspace root (i.e. it contains a `pnpm-workspace.yaml`) run as a normal workspace install so the full package set is materialized. Targets that are not workspace roots run with `--ignore-workspace` so each target directory is installed against its own `package.json`/`pnpm-lock.yaml` and pnpm does not walk up to a parent `pnpm-workspace.yaml` to write the lockfile (or install root dependencies) there.
- This action has no outputs.
