# Run Docker Compose Sandbox

Runs a repository-defined Docker Compose test sandbox through the deterministic lifecycle engine [`@repo-toolkit/compose-sandbox`](https://github.com/egose/repo-toolkit/tree/main/packages/compose-sandbox) (`repo-toolkit-compose-sandbox`). The action is a thin composite wrapper: it resolves the pinned toolkit CLI, invokes the engine with a validated config file, writes a redacted GitHub summary from the engine result manifest, and optionally uploads the engine evidence directory.

## Responsibilities

| Layer | Owns | Does not own |
| --- | --- | --- |
| **Action** (`egose/actions/compose-sandbox`) | Input validation, pinned CLI resolution via explicit override → workspace `node_modules/.bin` → `PATH` → exact-version `asdf` install, array-based invocation without shell evaluation, `always()` summary/artifact steps, stable outputs from the engine manifest, redacted logging | Compose startup, readiness polling, test execution, log collection, cleanup |
| **Engine** (`@repo-toolkit/compose-sandbox`) | `validate → prepare → start → wait → test → collect evidence → clean up`, structured `docker compose` arrays, TCP/HTTP/service probes, bounded evidence (`ps.json`, `logs.txt`, `result.json`), signal/timeout/cleanup guarantees | Checkout, package installation, GitHub artifact upload, step summaries |
| **Consumer** (calling repository) | `actions/checkout`, installing project dependencies (`pnpm`/`npm`/`yarn`/`Bats`/`Playwright`/clients), providing a valid toolkit config file, providing a runner with Docker Compose v2 | Action-internal binary resolution, engine lifecycle implementation |

Check responsibilities before filing issues: service definitions, probes, and test commands belong in the toolkit config file, not as action inputs.

## Prerequisites

The caller must provide before invoking the action:

1. **Checkout** – `actions/checkout` (or equivalent) so `cwd` and `config` exist.
2. **Project dependencies** – install whatever the sandbox test needs (e.g. `pnpm install --frozen-lockfile`, `npm ci`, Playwright browsers, Bats, `mongosh`, `psql` client). The action never installs consumer toolchains.
3. **Valid toolkit config** – a JSON, `.mjs`, or `.cjs` file loadable by `@repo-toolkit/publish-package` `loadConfigFile` (see engine [README](https://github.com/egose/repo-toolkit/tree/main/packages/compose-sandbox) and `website/docs/packages/compose-sandbox.md`).
4. **Docker Compose v2** – runner must have `docker compose` (not legacy `docker-compose`). Engine preflights `docker compose version`.

`--help` and `--dry-run` require neither Docker nor network access.

## Usage

All examples pin both the action and the toolkit to immutable refs. Replace `<commit-sha>` with the exact commit SHA from the release you intend to run (check the release notes for the tested `repo-toolkit-version`, current default `0.18.0`).

### Minimal

```yaml
jobs:
  sandbox:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1

      - uses: actions/setup-node@820762786026740c76f36085b0efc47a31fe5020
        with: { node-version: '26' }

      - run: pnpm install --frozen-lockfile

      - name: Run integration sandbox
        id: sandbox
        uses: egose/actions/compose-sandbox@<commit-sha>
        with:
          config: sandbox/ci-sandbox.mjs
          artifact-name: compose-logs-${{ matrix.attempt }}
```

### Database-shaped (mixed TCP/HTTP/one-shot + Bats)

Mirrors the `_database-tools` integration sandbox: two Compose files, environment file, bind-mount preparation, TCP + HTTP + `service-completed` probes, Bats test command, volume/orphan cleanup, and per-matrix artifact names.

Toolkit config `sandbox/database-sandbox.mjs`:

```js
export default {
  cwd: '.',
  compose: {
    files: ['sandbox/docker-compose.yml', 'sandbox/docker-compose.ci.yml'],
    envFile: 'sandbox/.env.dev',
    projectName: 'db-it',
  },
  prepare: {
    directories: ['sandbox/data/pg', 'sandbox/data/mongo', 'sandbox/data/minio'],
    copies: [{ from: 'sandbox/assets', to: 'sandbox/work/assets' }],
  },
  readiness: [
    { type: 'tcp', host: '127.0.0.1', port: 5432 },
    { type: 'tcp', host: '127.0.0.1', port: 27017 },
    { type: 'http', url: 'http://127.0.0.1:9000/minio/health/live' },
    { type: 'service-completed', service: 'minio-init' },
  ],
  test: { executable: 'pnpm', args: ['exec', 'bats', 'tests/integration'] },
  evidence: { directory: '.ci-logs', capture: 'onFailure' },
  cleanup: { volumes: true, removeOrphans: true, paths: ['sandbox/data/pg', 'sandbox/data/mongo'] },
};
```

Workflow:

```yaml
- name: Run database sandbox
  id: db-sandbox
  uses: egose/actions/compose-sandbox@<commit-sha>
  with:
    config: sandbox/database-sandbox.mjs
    cwd: ${{ github.workspace }}
    repo-toolkit-version: 0.18.0
    artifact-name: integration-service-logs-${{ matrix.startup-attempt }}
    artifact-policy: failure
```

### Template-shaped (three HTTP endpoints + Playwright)

Mirrors the `_vite-fastapi-postgres-template` Playwright sandbox: single Compose file, three HTTP probes, Playwright test command, always-capture evidence for post-run debugging.

Toolkit config `sandbox/app-sandbox.mjs`:

```js
export default {
  cwd: '.',
  compose: { files: ['sandbox/docker-compose.yml'], projectName: 'vfpt' },
  readiness: [
    { type: 'http', url: 'http://127.0.0.1:8000/api/v1/info' },
    { type: 'http', url: 'http://127.0.0.1:3000/health' },
    { type: 'http', url: 'http://127.0.0.1:8080/auth/health' },
  ],
  test: { executable: 'pnpm', args: ['playwright', 'test'] },
  evidence: { directory: '.ci-logs', capture: 'always' },
  cleanup: { volumes: true, removeOrphans: true },
};
```

Workflow:

```yaml
- name: Run app sandbox
  id: app-sandbox
  uses: egose/actions/compose-sandbox@<commit-sha>
  with:
    config: sandbox/app-sandbox.mjs
    artifact-name: playwright-logs
    artifact-policy: always
```

> The examples above illustrate the intended contract. They do not claim that `_database-tools` or `_vite-fastapi-postgres-template` have been migrated; repository migrations are tracked separately and retain their existing `actions/checkout`, setup, matrix, and permission policies.

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `config` | Yes | — | Path to the toolkit config file (JSON, `.mjs`, or `.cjs`). Resolved relative to `cwd`. |
| `cwd` | No | `${{ github.workspace }}` | Working directory the engine resolves relative paths against. Must be inside the workspace when provided. |
| `compose-sandbox-bin` | No | `` | Explicit path to the `repo-toolkit-compose-sandbox` executable. When set, bypasses workspace/`PATH`/`asdf` resolution. Useful for local development and fixture tests. |
| `repo-toolkit-version` | No | `0.18.0` | Exact `repo-toolkit` version to install via `asdf` when the binary is not found. Must be an exact semver; `latest` is rejected. Pinned to the version tested with this action release. |
| `repo-toolkit-plugin-url` | No | `https://github.com/egose/repo-toolkit.git` | Git URL for the `repo-toolkit` `asdf` plugin. |
| `artifact-name` | No | `compose-sandbox-logs` | Name of the GitHub artifact uploaded from the evidence directory. Ignored when `artifact-policy` is `never` or when no evidence is produced. |
| `artifact-policy` | No | `failure` | When to upload evidence. One of `failure` (only on sandbox failure), `always`, or `never`. |
| `artifact-retention-days` | No | `` | Retention days for the uploaded artifact. Empty uses the repository default. Must be a positive integer when set. |

No input accepts a multiline shell command. Test and readiness commands belong in the structured toolkit config (`test.executable` + `args` arrays).

### Pinned toolkit version

`repo-toolkit-version` defaults to the exact version tested with this action release (`0.18.0`), not `latest`. Every network installation path validates that the requested version is an exact semver and installs that version only. Third-party GitHub Actions used by the action itself are pinned to full commit SHAs. Consumers should keep `uses: egose/actions/compose-sandbox@<sha>` pinned to a commit SHA as well.

## Outputs

| Name | Description |
| --- | --- |
| `outcome` | Lifecycle outcome from the engine manifest: `success` or `failure`. |
| `failed-phase` | Phase that failed when `outcome` is `failure` (`validate`, `prepare`, `preflight`, `start`, `readiness`, `test`, `evidence`, or `cleanup`). Empty on success. |
| `evidence-directory` | Path to the evidence directory (`ps.json`, `logs.txt`, `result.json`), resolved relative to `cwd`. Empty when no evidence was produced. |
| `result-manifest` | Path to `result.json` inside the evidence directory. Machine-readable manifest containing `phase`, `outcome`, `timings`, `evidenceFiles`, and sanitized `errors`. |
| `artifact-name` | Name of the uploaded artifact when an upload was performed, otherwise empty. |

Outputs and the GitHub step summary are sourced from the validated engine `result.json` manifest, never by parsing human log text. Manifest values are validated without `eval`/`source`; malformed manifests fail the action without exposing secrets. `test.env` and probe `env` values are never written to logs, summaries, or outputs.

## Artifact and summary behavior

- **Engine invocation** runs in its own composite step.
- **Summary** (`GITHUB_STEP_SUMMARY`) and **artifact upload** each run in separate steps under `if: always()` so they execute even when the engine fails. Engine failure remains the action outcome; artifact upload failures are surfaced without turning a failed sandbox into success.
- Default `artifact-policy: failure` uploads only after failure. `always` uploads on success and failure; `never` disables upload.
- The action uploads only the bounded engine evidence directory, never unbounded raw Compose logs.

## Security

- Every caller-controlled value is passed to `run.sh` through environment variables (`COMPOSE_SANDBOX_INPUT_*` + `COMPOSE_SANDBOX_ACTION_PATH`). No input is interpolated into shell source or evaluated via `bash -c`/`eval`.
- CLI invocation uses Bash arrays for executable + arguments; whitespace or metacharacters in `config`/`cwd` are passed as single literal arguments.
- Environment values, config contents, and probe secrets are never echoed to logs or summaries; result manifest errors are sanitized and ANSI-stripped.
- No `latest` or unpinned `npx` downloads. Network installs use the exact `repo-toolkit-version`.

## Migrating consumers

Consumers keep their existing `actions/checkout`, `actions/setup-node`, `pnpm`/`npm`/`yarn` installs, matrix definitions, and permissions. To adopt this action:

1. Install Docker Compose v2 on the runner (GitHub-hosted `ubuntu-24.04` already has it).
2. Move repository-specific readiness and test behavior into a toolkit config file (`test.executable`/`args` arrays, `readiness` probes).
3. Replace `make DAEMON=true up` / `make logs` / `make down` or raw `docker-compose` blocks with a single `uses: egose/actions/compose-sandbox@<sha>` step per the examples above.

See the engine package docs for full configuration reference:

- [`@repo-toolkit/compose-sandbox` README](https://github.com/egose/repo-toolkit/tree/main/packages/compose-sandbox)
- [`website/docs/packages/compose-sandbox.md`](https://github.com/egose/repo-toolkit/blob/main/website/docs/packages/compose-sandbox.md)
