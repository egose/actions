## Overview

This GitHub Action automates building Docker container images and pushing them to a container registry. It combines the functionality of the following existing GitHub actions:

- [actions/cache](https://github.com/actions/cache)
- [docker/login-action](https://github.com/docker/login-action)
- [docker/metadata-action](https://github.com/docker/metadata-action)
- [docker/setup-buildx-action](https://github.com/docker/setup-buildx-action)
- [docker/build-push-action](https://github.com/docker/build-push-action)
- [aquasecurity/trivy-action](https://github.com/aquasecurity/trivy-action)
- [github/codeql-action/upload-sarif](https://github.com/github/codeql-action)

## Usage

### Basic

By default, it uses `.tool-versions` file located in the root directory to install asdf plugins.

```yaml
name: Basic

on: push

jobs:
  tools:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v3
      - name: Build and Push
        uses: egose/actions/docker-build-push@v0.2.9
        with:
          registry-url: ghcr.io
          registry-username: ${{ github.actor }}
          registry-password: ${{ secrets.GITHUB_TOKEN }}
          image-name: egose/myapp
          metadata-tags: |
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=semver,pattern={{major}}
```

## Inputs

The following inputs can be used as `step.with` keys:

| Name                | Type       | Required | Description                                      |
| ------------------- | ---------- | -------- | ------------------------------------------------ |
| `registry-url`      | String     | Yes      | Docker container registry server URL             |
| `registry-username` | String     | Yes      | Docker container registry username               |
| `registry-password` | String     | Yes      | Docker container registry password               |
| `image-name`        | String     | Yes      | Docker image name                                |
| `metadata-tags`     | List       | Yes      | List of tags as key-value pair attributes        |
| `metadata-labels`   | List       | No       | List of labels as key-value pair attributes      |
| `docker-context`    | String     | No       | Docker build's context                           |
| `docker-file`       | String     | No       | Path to the Dockerfile                           |
| `docker-args`       | StrListing | No       | List of build args as key-value pair attributes  |
| `trivy`             | Bool       | No       | If `true`, it runs `Trivy` vulnerability scanner |

## Outputs

The following outputs are available:

| Name                    | Type   | Description                                                                                                                                                     |
| ----------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `docker-version`        | String | Docker image version                                                                                                                                            |
| `docker-tags`           | String | Docker tags                                                                                                                                                     |
| `docker-labels`         | String | Docker labels                                                                                                                                                   |
| `docker-annotations`    | String | [Annotations](https://github.com/moby/buildkit/blob/master/docs/annotations.md)                                                                                 |
| `metadata-json`         | String | JSON output of tags and labels                                                                                                                                  |
| `bake-file-tags`        | File   | [Bake file definition](https://docs.docker.com/build/bake/reference/) path with tags                                                                            |
| `bake-file-labels`      | File   | [Bake file definition](https://docs.docker.com/build/bake/reference/) path with labels                                                                          |
| `bake-file-annotations` | File   | [Bake file definition](https://docs.docker.com/build/bake/reference/) path with [annotations](https://github.com/moby/buildkit/blob/master/docs/annotations.md) |
