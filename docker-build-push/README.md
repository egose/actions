# Docker Build Push

Builds a Docker image, pushes it to a registry, and exposes the generated Docker metadata as action outputs.

## What It Does

- Logs in to the target container registry.
- Generates tags, labels, and annotations with `docker/metadata-action`.
- Builds and pushes the image with `docker/build-push-action`.
- Reuses a local Buildx layer cache between runs.
- Optionally runs Trivy and uploads SARIF results to the GitHub Security tab.

## Usage

### Basic

```yaml
name: Publish Image

on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  docker:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      security-events: write

    steps:
      - uses: actions/checkout@v4

      - name: Build and push image
        uses: egose/actions/docker-build-push@main
        with:
          registry-url: ghcr.io
          registry-username: ${{ github.actor }}
          registry-password: ${{ secrets.GITHUB_TOKEN }}
          image-name: egose/myapp
          metadata-tags: |
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha
```

### Run Trivy After Pushing

```yaml
- name: Build, push, and scan image
  uses: egose/actions/docker-build-push@main
  with:
    registry-url: ghcr.io
    registry-username: ${{ github.actor }}
    registry-password: ${{ secrets.GITHUB_TOKEN }}
    image-name: egose/myapp
    metadata-tags: |
      type=ref,event=branch
      type=sha
    trivy: 'true'
```

### Share Metadata Between Labels And Annotations

```yaml
- name: Build and push image
  uses: egose/actions/docker-build-push@main
  with:
    registry-url: ghcr.io
    registry-username: ${{ github.actor }}
    registry-password: ${{ secrets.GITHUB_TOKEN }}
    image-name: egose/myapp
    metadata-tags: |
      type=sha
    metadata-labels-annotations: |
      org.opencontainers.image.source=${{ github.server_url }}/${{ github.repository }}
      org.opencontainers.image.revision=${{ github.sha }}
    metadata-labels: |
      org.opencontainers.image.title=myapp
```

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `registry-url` | Yes |  | Container registry hostname, for example `ghcr.io`. |
| `registry-username` | Yes |  | Username used to log in to the registry. |
| `registry-password` | Yes |  | Password or token used to log in to the registry. |
| `image-name` | Yes |  | Image name without the registry prefix. |
| `metadata-tags` | Yes |  | Newline-separated tag rules in `docker/metadata-action` format. |
| `metadata-labels` | No |  | Newline-separated label rules in `docker/metadata-action` format. |
| `metadata-annotations` | No |  | Newline-separated annotation rules in `docker/metadata-action` format. |
| `metadata-labels-annotations` | No |  | Newline-separated rules applied to both labels and annotations. If the same key appears in both this input and a specific metadata input, the specific input wins. |
| `docker-context` | No |  | Build context passed to `docker/build-push-action`. |
| `docker-file` | No |  | Path to the Dockerfile. |
| `docker-args` | No |  | Additional build args. `BUILD_TIMESTAMP` is always injected automatically. |
| `docker-outputs` | No |  | Output destinations passed through to `docker/build-push-action`. |
| `trivy` | No | `"false"` | Runs Trivy, converts the report to SARIF, and uploads it when set to `true`. |

## Outputs

| Name | Description |
| --- | --- |
| `docker-version` | Generated Docker image version reported by the metadata step. |
| `docker-tags` | Generated image tags. |
| `docker-labels` | Generated image labels. |
| `docker-annotations` | Generated [BuildKit annotations](https://github.com/moby/buildkit/blob/master/docs/annotations.md). |
| `metadata-json` | Raw JSON output from `docker/metadata-action`. |
| `bake-file-tags` | Bake definition file containing generated tags. |
| `bake-file-labels` | Bake definition file containing generated labels. |
| `bake-file-annotations` | Bake definition file containing generated annotations. |
| `bake-file` | Bake definition file containing generated tags, labels, and annotations. |

## Notes

- This action always pushes the built image. There is no build-only mode.
- The image reference is constructed as `${{ inputs.registry-url }}/${{ inputs.image-name }}`.
- `metadata-labels-annotations` is appended to both `labels` and `annotations` for `docker/metadata-action`, then the specific input is appended after it so `metadata-labels` and `metadata-annotations` override shared keys.
- The Trivy steps require `security-events: write` permission if you want SARIF uploaded to GitHub code scanning.
