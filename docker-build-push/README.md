## About

GitHub Action to build docker container image and push to the container registry.

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

| Name                | Type       | Required | Description                                     |
| ------------------- | ---------- | -------- | ----------------------------------------------- |
| `registry-url`      | String     | Yes      | Docker container registry server URL            |
| `registry-username` | String     | Yes      | Docker container registry username              |
| `registry-password` | String     | Yes      | Docker container registry password              |
| `image-name`        | String     | Yes      | Docker image name                               |
| `metadata-tags`     | List       | Yes      | List of tags as key-value pair attributes       |
| `metadata-labels`   | List       | No       | List of labels as key-value pair attributes     |
| `docker-context`    | String     | No       | Docker build's context                          |
| `docker-file`       | String     | No       | Path to the Dockerfile                          |
| `docker-args`       | StrListing | No       | List of build args as key-value pair attributes |
