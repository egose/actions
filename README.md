# GitHub Actions

This repository contains several reusable composite GitHub Actions.

## Modules

| Module | Purpose |
| --- | --- |
| [`asdf-install`](./asdf-install/README.md) | Installs the `asdf` CLI and adds it to `PATH`. |
| [`asdf-tools`](./asdf-tools/README.md) | Installs `asdf` and tool versions from `.tool-versions`. |
| [`docker-build-push`](./docker-build-push/README.md) | Builds and pushes a Docker image, with optional Trivy scanning. |
| [`npm-packages`](./npm-packages/README.md) | Runs `npm install` across one or more package directories. |
| [`oc-login`](./oc-login/README.md) | Ensures `oc` exists and logs into an OpenShift cluster. |
| [`pnpm-packages`](./pnpm-packages/README.md) | Runs `pnpm install` across one or more package directories. |
| [`pre-commit`](./pre-commit/README.md) | Runs `pre-commit` and can commit hook-generated changes. |
| [`precommit`](./precommit/README.md) | Compatibility wrapper that delegates to [`pre-commit`](./pre-commit/README.md). |
| [`release-tag`](./release-tag/README.md) | Generates release candidate PRs from semantic versioning rules. |
| [`yarn-packages`](./yarn-packages/README.md) | Runs `yarn install` across one or more package directories. |

## Root Action

The root `action.yml` is a compatibility wrapper around [`docker-build-push`](./docker-build-push/README.md). New usage should prefer the explicit module path:

```yaml
uses: egose/actions/docker-build-push@main
```

The [`precommit`](./precommit/README.md) path is a compatibility wrapper around [`pre-commit`](./pre-commit/README.md).
