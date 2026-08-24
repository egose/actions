# Docker Build Push

Builds a Docker image, pushes it to any OCI-compatible registry, and exposes generated metadata and image digests as action outputs.

## What It Does

- Logs in to the target container registry.
- Generates tags, labels, and annotations with `docker/metadata-action`.
- Builds and pushes the image with `docker/build-push-action`.
- Reuses a local Buildx layer cache between runs.
- Supports the backward-compatible `direct` build-and-push mode.
- Supports a single-platform `gated` mode that builds locally, runs optional pre-push checks and Trivy, then pushes and verifies the exact local image config digest.
- Optionally generates an SPDX JSON SBOM and uploads SARIF results to the GitHub Security tab.
- Optionally creates GitHub provenance and SBOM attestations for the verified image.

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

`direct` is the default mode for compatibility. Its Trivy scan runs after the image is pushed.

### Scan Before Publishing

Use `gated` mode when registry tags must not change until checks pass:

```yaml
- name: Build, scan, and publish the verified image
  id: image
  uses: egose/actions/docker-build-push@main
  with:
    registry-url: registry.example.com
    registry-username: ${{ secrets.REGISTRY_USERNAME }}
    registry-password: ${{ secrets.REGISTRY_PASSWORD }}
    image-name: team/myapp
    metadata-tags: |
      type=semver,pattern={{version}}
      type=semver,pattern={{major}}.{{minor}}
    metadata-labels: |
      org.opencontainers.image.revision=${{ github.sha }}
    docker-context: .
    publish-mode: gated
    pre-push-command: docker run --rm "$IMAGE_REF" myapp --version
    trivy: 'true'
    sbom: 'true'
    attest-provenance: 'true'
    attest-sbom: 'true'

- name: Use the verified publication outputs
  run: |
    printf 'Image: %s\n' "$IMAGE_REF"
    printf 'Manifest: %s\n' "$MANIFEST_DIGEST"
  env:
    IMAGE_REF: ${{ steps.image.outputs.image-ref }}
    MANIFEST_DIGEST: ${{ steps.image.outputs.manifest-digest }}
```

The registry host is not tied to GHCR. For an already-authenticated Docker client or an unauthenticated local registry, set `registry-login: 'false'` and omit credentials.

GitHub attestations are optional. Callers enabling them must grant `id-token: write` and `attestations: write`. Callers creating artifact storage records must also grant `artifact-metadata: write`:

```yaml
permissions:
  artifact-metadata: write
  attestations: write
  id-token: write
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
| `registry-username` | When logging in |  | Username used to log in to the registry. |
| `registry-password` | When logging in |  | Password or token used to log in to the registry. |
| `registry-login` | No | `"true"` | Log in before publishing. Set to `"false"` for an already-authenticated client or an unauthenticated local registry. |
| `image-name` | Yes |  | Image name without the registry prefix. |
| `metadata-tags` | Yes |  | Newline-separated tag rules in `docker/metadata-action` format. |
| `metadata-labels` | No |  | Newline-separated label rules in `docker/metadata-action` format. |
| `metadata-annotations` | No |  | Newline-separated annotation rules in `docker/metadata-action` format. |
| `metadata-labels-annotations` | No |  | Newline-separated rules applied to both labels and annotations. If the same key appears in both this input and a specific metadata input, the specific input wins. |
| `docker-context` | No |  | Build context passed to `docker/build-push-action`. |
| `docker-file` | No |  | Path to the Dockerfile. |
| `docker-args` | No |  | Additional build args. `BUILD_TIMESTAMP` is always injected automatically. |
| `docker-outputs` | No |  | Output destinations passed through to `docker/build-push-action` in `direct` mode. Unsupported in `gated` mode. |
| `publish-mode` | No | `direct` | `direct` builds and pushes immediately; `gated` builds and checks a local single-platform image before publishing it unchanged. |
| `pre-push-command` | No |  | Trusted shell command run in `gated` mode with `IMAGE_REF` and `IMAGE_CONFIG_DIGEST` available. |
| `trivy` | No | `"false"` | Runs Trivy after push in `direct` mode or as a hard pre-push gate in `gated` mode. |
| `trivy-severity` | No | `HIGH,CRITICAL` | Comma-separated severities that fail a gated scan. |
| `trivy-ignore-unfixed` | No | `"true"` | Ignore vulnerabilities without fixes during a gated scan. |
| `trivy-sarif-file` | No | `trivy-results.sarif` | Path for the Trivy SARIF report in gated mode. |
| `upload-sarif` | No | `"true"` | Upload Trivy SARIF to GitHub code scanning. |
| `sbom` | No | `"false"` | Generate an SPDX JSON SBOM from the gated local image. |
| `sbom-file` | No | `image-sbom.spdx.json` | Path for the generated image SBOM. |
| `attest-provenance` | No | `"false"` | Create GitHub build provenance for the verified image. Requires gated mode. |
| `attest-sbom` | No | `"false"` | Create a GitHub attestation from the generated SBOM. Requires `sbom: "true"` and gated mode. |
| `attest-push-to-registry` | No | `"true"` | Attach enabled attestations to the OCI image in the registry. |
| `attest-create-storage-record` | No | `"true"` | Create GitHub artifact metadata storage records. Requires registry attachment. |

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
| `image-ref` | Primary local image reference in gated mode. |
| `image-config-digest` | Config digest of the checked local image in gated mode. |
| `manifest-digest` | Primary manifest digest reported after publication. |
| `sbom-path` | Generated image SBOM path when enabled. |
| `provenance-attestation-id` | GitHub ID of the provenance attestation. |
| `provenance-attestation-url` | GitHub URL of the provenance attestation. |
| `provenance-bundle-path` | Local path to the provenance attestation bundle. |
| `provenance-storage-record-ids` | GitHub artifact metadata storage record IDs for the provenance attestation. |
| `sbom-attestation-id` | GitHub ID of the SBOM attestation. |
| `sbom-attestation-url` | GitHub URL of the SBOM attestation. |
| `sbom-bundle-path` | Local path to the SBOM attestation bundle. |
| `sbom-storage-record-ids` | GitHub artifact metadata storage record IDs for the SBOM attestation. |

## Notes

- The image reference is constructed as `${{ inputs.registry-url }}/${{ inputs.image-name }}`.
- `registry-url` must be a registry host such as `ghcr.io`, `registry.example.com:5000`, or `docker.io`; do not include a URL scheme or trailing slash.
- `metadata-labels-annotations` is appended to both `labels` and `annotations` for `docker/metadata-action`, then the specific input is appended after it so `metadata-labels` and `metadata-annotations` override shared keys.
- Gated mode supports one runner-native platform because it loads and tests the image with Docker before publication. Use direct mode for custom or multi-platform Buildx outputs.
- Gated mode rejects metadata annotations because loading an image into Docker does not preserve manifest annotations. OCI labels are supported.
- Gated mode authenticates only after the local checks and vulnerability gate pass, pushes each generated tag from the same local image, and verifies every remote manifest config digest against the local config digest.
- `pre-push-command` is executable code and should only contain trusted workflow configuration. The command receives `IMAGE_REF` and `IMAGE_CONFIG_DIGEST`.
- The Trivy upload requires `security-events: write`. Set `upload-sarif: 'false'` when that GitHub-specific integration is unavailable or unwanted.
- Attestations use GitHub Artifact Attestations and therefore require GitHub.com plus the documented job permissions. Private and internal repositories require GitHub Enterprise Cloud; GitHub Enterprise Server is not supported.
- Registry attachment uses the existing Docker login and requires an OCI registry that supports attestation/referrer artifacts. Set `attest-push-to-registry: 'false'` and `attest-create-storage-record: 'false'` to keep attestations in GitHub only when the target registry does not support attachment.
- Artifact metadata storage records are available only to organization-owned repositories. When requested, the action fails if GitHub does not return a storage record ID; disable `attest-create-storage-record` for user-owned repositories.
