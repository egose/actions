# Install asdf Tools

Installs `asdf`, restores the `~/.asdf` cache, and installs the tool versions defined in a `.tool-versions` file.

## What It Does

- Installs the `asdf` CLI with [`asdf-install`](../asdf-install/README.md).
- Restores and updates the `~/.asdf` directory with `actions/cache`.
- Adds plugins listed in `.tool-versions`.
- Optionally adds extra plugins from the `plugins` input.
- Installs the requested tool versions and runs `asdf reshim`.

## Usage

### Basic

```yaml
name: Setup Tools

on: push

jobs:
  tools:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install tools from .tool-versions
        uses: egose/actions/asdf-tools@main
```

### Use a Different `.tool-versions` Directory

```yaml
- name: Install tools from app/.tool-versions
  uses: egose/actions/asdf-tools@main
  with:
    context: ./app
```

### Add Extra Plugin Sources

```yaml
- name: Install tools with extra plugins
  uses: egose/actions/asdf-tools@main
  with:
    plugins: |
      docker-compose=https://github.com/virtualstaticvoid/asdf-docker-compose.git
      poetry=https://github.com/asdf-community/asdf-poetry.git
```

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `version` | No | `v0.19.0` | Version of the `asdf` binary to install. |
| `plugins` | No | `""` | Newline-separated list of extra plugins in `<plugin>=<url>` format. |
| `context` | No | `.` | Directory that contains the `.tool-versions` file. |

## Notes

- This action expects a `.tool-versions` file to exist in the selected `context` directory.
- The action currently supports Linux and macOS runners on `amd64` and `arm64`.
- Windows runners are not currently supported.
- Cache invalidation is based on `hashFiles('**/.tool-versions')`, so updates to any `.tool-versions` file in the repository will refresh the cache key.
