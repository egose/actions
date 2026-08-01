# Sync Docs to Confluence

Publishes a folder of Markdown documentation to Confluence, mirroring the
directory structure as a page hierarchy. Each Markdown file becomes one
Confluence page under the configured parent; each sub-folder becomes a parent
page. Local images referenced from the markdown are uploaded as Confluence
attachments and inline-rendered as `<ac:image><ri:attachment /></ac:image>`
macros; remote images stay as `<ac:image><ri:url />`.

The action is a thin composite wrapper around the
[`@repo-toolkit/confluence`](https://github.com/egose/repo-toolkit/tree/main/packages/confluence)
CLI; install the package in the consuming repository so the action can find it
in `node_modules/.bin`.

## What It Does

- Walks `folder` recursively for `*.md` files (skipping dotfile directories).
- Resolves the Confluence `spaceId` from `space-key` via the Confluence REST API v2.
- For each sub-folder path segment, finds or creates a parent page (cached per run by parent id + title).
- For each Markdown file: converts the body to Confluence storage format, uploads local images as attachments and rewrites the corresponding placeholders, then PUTs the page with `version.number = current + 1` (optimistic concurrency — concurrent writes get HTTP 409).
- Skips pages whose body is unchanged when `skip-unchanged` is `true` (default).

## Usage

### Basic

```yaml
name: Sync Docs to Confluence

on:
  push:
    branches: [main]
    paths: ['docs/**']

jobs:
  docs-as-code:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: pnpm/action-setup@v4
        with:
          version: 10

      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: pnpm

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      - name: Sync Docs to Confluence
        uses: egose/actions/confluence@main
        with:
          folder: docs
          username: abc@xyz.com
          api-token: ${{ secrets.CONFLUENCE_API_TOKEN }}
          confluence-base-url: https://mydomain.atlassian.net/wiki
          space-key: ~1234
          parent-page-id: '123456789'
```

### Dry-run Planning

Useful to verify the directory walk picks up the expected pages without
touching Confluence:

```yaml
- uses: egose/actions/confluence@main
  with:
    folder: docs
    dry-run: 'true'
```

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `folder` | No | `docs` | Folder containing the documentation to publish. |
| `username` | No | `${{ github.actor }}` | Confluence username or email. |
| `api-token` | No | `` | Confluence API token (NOT your account password). Prefer this over `password`. |
| `password` | No | `` | Alias for `api-token`; kept for backwards compatibility with `Bhacaz/docs-as-code-confluence`. |
| `confluence-base-url` | No | `` | Confluence URL with `/wiki` (e.g. `https://mydomain.atlassian.net/wiki`). |
| `space-key` | No | `` | Confluence space key (`ENG`, `~1234`, ...). Resolved to a `spaceId` via the API. |
| `parent-page-id` | No | `` | Numeric Confluence page id under which docs will be published. Must be `^[0-9]+$`. |
| `version-message` | No | `` | Suffix appended to every page/attachment PUT. |
| `skip-unchanged` | No | `true` | Skip pages whose body is byte-identical to the current Confluence storage value. |
| `dry-run` | No | `false` | Walk the doc tree and log the plan without making API calls. |
| `cwd` | No | `${{ github.workspace }}` | Working directory the CLI resolves `folder` against. |
| `confluence-bin` | No | `` | Path to the `repo-toolkit-confluence` binary. Auto-resolved from `node_modules/.bin` when empty. |

## Security Notes

- Store the Confluence API token as a repository secret and reference it via `${{ secrets.* }}`.
- Authentication uses HTTP Basic with `<username>:<apiToken>`; never send your account password.
- The CLI escapes all HTML output and neutralises `]]>` inside code blocks; attachment filenames are path-separator-stripped before being emitted into `<ri:attachment ri:filename="…"/>`.

## Binary Resolution

`run.sh` resolves the `repo-toolkit-confluence` CLI in this order:

1. `confluence-bin` input (explicit override).
2. `<workspace>/node_modules/.bin/repo-toolkit-confluence` (when the consuming repo listed `@repo-toolkit/confluence` as a dep).
3. `<action_path>/node_modules/.bin/repo-toolkit-confluence` (for repo-internal fixture tests).
4. `repo-toolkit-confluence` in `PATH`.
5. `npx -y @repo-toolkit/confluence` (last resort; downloads on every run — not recommended for production).

Add `@repo-toolkit/confluence` to the consuming repo's `devDependencies` (or
`dependencies`) and run `pnpm install` before invoking the action for the fastest
startup.
