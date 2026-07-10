# Install asdf

Installs the `asdf` CLI on Linux and macOS runners and adds both the binary directory and `asdf` shims to `PATH`.

## What It Does

- Detects the current runner OS and CPU architecture.
- Downloads the matching `asdf` release asset from GitHub.
- Installs the `asdf` binary into the runner temp directory.
- Adds the binary directory and `${ASDF_DATA_DIR:-$HOME/.asdf}/shims` to `PATH`.

## Usage

### Basic

```yaml
name: Install asdf

on: push

jobs:
  tools:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install asdf
        uses: egose/actions/asdf-install@main
```

### Pin a Specific Version

```yaml
- name: Install asdf v0.19.0
  uses: egose/actions/asdf-install@main
  with:
    version: v0.19.0
```

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `version` | No | `v0.19.0` | Version of the `asdf` binary to install. |

## Notes

- This action supports Linux and macOS runners on `amd64` and `arm64`.
- Windows runners are not currently supported.
- This action installs only the `asdf` CLI. Use [`asdf-tools`](../asdf-tools/README.md) to restore the cache and install tool versions from `.tool-versions`.
