# GitHub Actions

This repository contains several reusable composite GitHub Actions.

## Modules

| Module | Purpose |
| --- | --- |
| [`asdf-tools`](./asdf-tools/README.md) | Installs `asdf` and tool versions from `.tool-versions`. |
| [`docker-build-push`](./docker-build-push/README.md) | Builds and pushes a Docker image, with optional Trivy scanning. |
| [`precommit`](./precommit/README.md) | Runs `pre-commit` and can commit hook-generated changes. |
| [`release-tag`](./release-tag/README.md) | Generates release candidate PRs from semantic versioning rules. |
| [`yarn-packages`](./yarn-packages/README.md) | Runs `yarn install` across one or more package directories. |

## Root Action

The root `action.yml` is a compatibility wrapper around [`docker-build-push`](./docker-build-push/README.md). New usage should prefer the explicit module path:

```yaml
uses: egose/actions/docker-build-push@main
```
