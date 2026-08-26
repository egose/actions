# Compose Sandbox GitHub Action

Created: 2026-08-25 18:00:40

Status: pending

## Objective

Add a reusable `compose-sandbox` composite GitHub Action that invokes the generic `repo-toolkit-compose-sandbox` lifecycle engine, uploads its evidence, writes a concise GitHub summary, and exposes stable outputs without reimplementing Docker Compose orchestration.

The action must support workflows shaped like `_database-tools` integration Bats tests and `_vite-fastapi-postgres-template` Playwright sandbox tests. Repository-specific checkout, tools, package installation, matrix policy, service definitions, configuration, and test commands remain in consuming repositories.

Required engine plan:

- `projects/_repo-toolkit/docs/tasks/20260825-180040-compose-sandbox-runner.md`

## Confirmed Reuse Opportunity

The existing template-local action already centralizes start, wait, test, logs, and stop, but hardcodes Make commands and application endpoints. The database workflow independently implements the same lifecycle with raw Compose commands and richer readiness checks.

The `_egose-actions` repository already provides the correct distribution model for reusable composite actions and already has a precedent for resolving a `repo-toolkit` CLI from an explicit input, workspace installation, `PATH`, asdf release, or package fallback.

Primary evidence:

- `README.md:1-29`
- `confluence/action.yml:45-98`
- `confluence/run.sh:47-194,239-282`
- `.github/workflows/test-confluence.yml:18-75`
- `.github/workflows/test-docker-build-push.yml:20-159`

## Scope

The first release must provide:

- A `compose-sandbox/action.yml` composite action and focused wrapper script.
- Inputs for project working directory, toolkit config path, toolkit binary override, and pinned toolkit installation version.
- Optional artifact name, retention, and upload policy inputs.
- Safe resolution and invocation of `repo-toolkit-compose-sandbox` without evaluating user inputs as shell source.
- Artifact upload from the engine's evidence directory on failure by default, with an explicit always/never policy.
- A concise GitHub step summary sourced from the engine's machine-readable result manifest.
- Outputs for lifecycle outcome, failed phase, evidence directory, result manifest, and artifact name when uploaded.
- Shell-level tests with fake binaries plus a real GitHub Actions fixture using Docker Compose.
- Documentation examples corresponding to both intended consumer repositories.

## Working Rules

- Do not implement Compose startup, readiness polling, test execution, evidence generation, or cleanup in this repository. Those belong to `@repo-toolkit/compose-sandbox`.
- Do not revert or rewrite unrelated worktree changes. Inspect `git status --short` before each task.
- Pass action expressions into scripts through environment variables. Do not interpolate config paths, commands, or other caller-controlled strings into shell source.
- Use arrays for CLI invocation. Do not construct a whitespace-delimited command string.
- Default to an exact toolkit version tested with the action release. Do not default to `latest` and do not use an unpinned `npx` download.
- Permit an explicit binary override for local development and fixture tests.
- Do not print environment values, config contents, or toolkit command environment to logs or summaries.
- Keep third-party action references pinned to full commit SHAs.
- Add completion evidence to this file as tasks finish. Code without required verification is not complete.

## Non-Goals

- Creating a reusable workflow with checkout, runner, permissions, matrices, or package installation policy.
- Installing Docker or supporting runners without Docker Compose v2.
- Defining shared PostgreSQL, MongoDB, MinIO, Keycloak, API, or frontend services.
- Accepting a multiline shell `script` input compatible with the current template-local action.
- Preserving the current `make DAEMON=true up`, `make logs`, or `make down` interface.
- Duplicating readiness endpoints as action inputs; probes belong in the toolkit config file.
- Migrating consumers in the same change.
- Refactoring the existing `confluence` action unless a small shared binary-resolution helper is proven safe and reduces duplication without changing its contract.

## Baseline Verification

Before implementation begins, record results for:

```sh
git status --short
npm run actionlint
npm run test:shell
pre-commit run --all-files
docker compose version
```

The task document was created from a clean worktree. If later baseline failures exist, record them before changing code and do not silently absorb unrelated remediation.

Unit-style shell tests should fake toolkit/asdf behavior and not need Docker or network access. The GitHub workflow fixture must exercise a released toolkit version against real Docker Compose before the action is released.

## Priorities

- P0: Required to avoid mutable tool installation, shell injection, leaked sandbox resources, hidden failures, or secret exposure.
- P1: Required for the initial action contract, outputs, artifact behavior, and automated tests.
- P2: Documentation and consumer-shaped examples required before release.

## Planned Action Contract

Expected usage:

```yaml
- name: Run integration sandbox
  id: sandbox
  uses: egose/actions/compose-sandbox@<commit-sha>
  with:
    config: sandbox/ci-sandbox.mjs
    artifact-name: integration-service-logs-${{ matrix.startup-attempt }}
```

Planned inputs:

```text
config                    required
cwd                       default: github.workspace
compose-sandbox-bin       optional explicit executable override
repo-toolkit-version      exact version tested by this action release
repo-toolkit-plugin-url   default: https://github.com/egose/repo-toolkit.git
artifact-name             default: compose-sandbox-logs
artifact-policy           failure | always | never; default: failure
artifact-retention-days   optional
```

Planned outputs:

```text
outcome
failed-phase
evidence-directory
result-manifest
artifact-name
```

The action must consume the engine's result manifest rather than parse human log text. Exact optional output names may be refined, but changes to the config-file boundary, exact-version default, or thin-wrapper ownership require a recorded maintainer decision.

## Execution Waves

1. Action contract and local wrapper tests: ACTBOX-01 and ACTBOX-02.
2. Artifact, summary, and failure behavior: ACTBOX-03.
3. Real GitHub Actions integration and docs: ACTBOX-04.
4. Independent final integration review: ACTBOX-05.

ACTBOX-02 and later depend on the matching toolkit CLI/result-manifest contract. The action may be scaffolded against an explicit fake binary before the toolkit is published, but release verification must use an exact published version.

## Detailed Tasks

### Task ACTBOX-01: Define The Composite Action Contract

Status: pending

Priority: P1

Suggested agent: GitHub Actions contract engineer

Dependencies: toolkit CSBOX-02 contract reviewed; implementation may use a fake binary

Primary ownership:

- `compose-sandbox/action.yml`
- `compose-sandbox/README.md`
- root `README.md` module entry
- initial `tests/fixtures/compose-sandbox/`

Finding:

No shared sandbox action exists. The template-local action's single `script` input and hardcoded Make/endpoints cannot represent the database sandbox safely or generically.

References:

- `README.md:5-19`
- `confluence/action.yml:45-98`

Implementation requirements:

1. Define the planned inputs and outputs with accurate descriptions, required/default behavior, and no multiline shell command input.
2. Pass every caller-controlled value to the wrapper through environment variables.
3. Keep GitHub-specific artifact and summary steps separate from the engine invocation step so they can run under `always()` as required.
4. Document that the caller must check out source, install project dependencies, and provide a valid toolkit config and Docker Compose v2 runner.
5. Add both database-shaped and template-shaped usage examples without claiming consumer migration has happened.

Acceptance criteria:

- `actionlint compose-sandbox/action.yml` passes through the repository's actionlint command.
- The root module table links to the action README.
- Documentation clearly separates action, engine, and consumer responsibilities.
- No action input is evaluated as shell source.

### Task ACTBOX-02: Resolve And Invoke The Pinned Toolkit CLI Safely

Status: pending

Priority: P0

Suggested agent: shell and supply-chain engineer

Dependencies: ACTBOX-01; toolkit CSBOX-06 complete; exact compatible toolkit release available before completion

Primary ownership:

- `compose-sandbox/run.sh`
- `tests/test-compose-sandbox.sh`
- focused fake executables under `tests/fixtures/compose-sandbox/`
- `package.json` test script registration if needed

Finding:

The wrapper needs zero-setup operation while retaining reproducibility. The existing Confluence wrapper demonstrates explicit/workspace/PATH/asdf/package resolution, but its default `latest` behavior and whitespace-delimited argument construction must not be copied into the new action.

References:

- `confluence/run.sh:47-194,239-282`
- `confluence/action.yml:49-72`
- `tests/test-confluence.sh:1-145`
Implementation requirements:

1. Resolve the CLI in this order: explicit override, consumer workspace `node_modules/.bin`, action/PATH installation, exact-version asdf installation, exact-version package fallback if retained.
2. Validate version input syntax and ensure every network installation path uses that exact version. Reject `latest`, empty resolved versions, and mutable package fallback.
3. Invoke the binary and flags with a Bash array, passing absolute validated `cwd` and config paths without `eval`, `bash -c`, or command-string expansion.
4. Preserve the toolkit's exit status while making its result manifest location available to later composite steps.
5. Test paths containing spaces and shell metacharacters, missing executables, failed installation, toolkit failure, and successful invocation. Assert that values are passed literally and not executed.
6. Avoid broad refactoring of `confluence/run.sh`; record a follow-up if a shared resolver becomes independently worthwhile.

Acceptance criteria:

- Shell tests prove explicit, workspace, PATH, asdf, and any package fallback resolution use the expected exact executable/version.
- A malicious-looking config/cwd value is passed as one literal argument and cannot create a marker file.
- Toolkit nonzero status remains nonzero and its result manifest remains available when produced.
- `npm run test:shell` passes.

### Task ACTBOX-03: Upload Evidence And Publish Redacted Outputs

Status: pending

Priority: P0

Suggested agent: CI failure-observability engineer

Dependencies: ACTBOX-02; toolkit CSBOX-05 result-manifest contract stable

Primary ownership:

- `compose-sandbox/action.yml`
- small focused helper under `compose-sandbox/` if needed
- `tests/test-compose-sandbox.sh`

Finding:

Both reference implementations need failure logs, but artifact naming and capture policy differ. The action should consume already-bounded engine evidence instead of running Compose commands after the engine has cleaned up.

References:

- `docker-build-push/action.yml:315-336`

Implementation requirements:

1. Read and validate the toolkit's machine-readable result manifest without sourcing or evaluating it as shell.
2. Set declared outputs and append a concise step summary containing outcome, failed phase, and artifact/evidence references only.
3. Upload the evidence directory according to `failure`, `always`, or `never`; use the pinned `actions/upload-artifact` commit already established in the repository unless intentionally upgraded everywhere by separate work.
4. Preserve action failure when the toolkit fails after artifact and summary steps execute. Artifact upload failure must be visible and must not turn a failed sandbox into success.
5. Reject artifact names or manifest paths that violate GitHub/action path constraints, and never include config environment values or raw command environments in outputs or summary.

Acceptance criteria:

- Success and failure fixtures set all applicable outputs consistently.
- Failure-policy tests show evidence upload is requested only after failure; always/never behave as documented.
- A malformed, missing, escaping, or secret-bearing manifest is handled without evaluating content or exposing secrets.
- The original sandbox failure remains the action outcome after evidence handling.
- `npm run actionlint` and `npm run test:shell` pass.

### Task ACTBOX-04: Add Real Compose CI And Consumer Documentation

Status: pending

Priority: P2

Suggested agent: GitHub Actions integration engineer

Dependencies: ACTBOX-03; exact toolkit version published after CSBOX-07

Primary ownership:

- `.github/workflows/test-compose-sandbox.yml`
- `tests/fixtures/compose-sandbox/`
- `compose-sandbox/README.md`
- root validation paths/scripts as needed

Finding:

Shell fakes can validate argument and installation behavior but cannot prove composite `if: always()` behavior, artifact upload, Docker cleanup, or compatibility with the published toolkit artifact on a GitHub-hosted runner.

References:

- `.github/workflows/test-confluence.yml:18-75`
- `.github/workflows/test-docker-build-push.yml:88-159`
- `.github/workflows/actionlint.yml:3-19`
- `projects/_repo-toolkit/docs/tasks/20260825-180040-compose-sandbox-runner.md`

Implementation requirements:

1. Add a minimal real-Compose fixture with a healthy long-running service, a successful one-shot service, and a deterministic test command.
2. Exercise success and forced-test-failure jobs through `uses: ./compose-sandbox`; verify outputs, summaries where observable, artifact creation, and no leaked containers/networks/volumes.
3. Install or resolve the exact published toolkit version declared as the action default. Do not test release behavior only against an unpublished sibling checkout.
4. Add workflow path filters for action, wrapper, fixture, and workflow changes.
5. Complete docs with pinned action usage and configurations matching the database mixed-probe sandbox and template HTTP-probe sandbox.
6. Document migration requirements: use `docker compose`, move repository-specific readiness/test behavior into toolkit config, and retain existing checkout/setup/matrix steps.

Acceptance criteria:

- GitHub-hosted success and expected-failure fixture jobs pass their assertions.
- Failure evidence is downloadable under the configured artifact name.
- Post-run checks find no fixture Compose resources.
- Documentation examples contain no mutable action or toolkit references.
- `npm run actionlint`, `npm run test:shell`, and `pre-commit run --all-files` pass.

### Task ACTBOX-05: Perform Independent Action Integration Review

Status: pending

Priority: P0

Suggested agent: independent GitHub Actions and supply-chain reviewer

Dependencies: ACTBOX-04

Primary ownership:

- review-only across `compose-sandbox/`, tests, workflow, and docs
- fixes limited to review findings
- this task document's completion evidence

Finding:

The final behavior crosses shell quoting, executable resolution, mutable dependency prevention, composite step conditions, artifact handling, and engine failure semantics. These boundaries require review independent of the main implementation.

References:

- all ACTBOX tasks and acceptance criteria
- `projects/_repo-toolkit/docs/tasks/20260825-180040-compose-sandbox-runner.md`
- `.pre-commit-config.yaml:1-43`

Implementation requirements:

1. Verify every action input and toolkit-derived value remains data rather than shell source.
2. Verify every installation path resolves the documented exact toolkit version and third-party actions use commit SHAs.
3. Verify toolkit failure, malformed manifest, artifact failure, cancellation, and action timeout cannot report false success or skip engine cleanup.
4. Verify docs, inputs, outputs, summary, result manifest, and published toolkit behavior agree.
5. Run shell, actionlint, pre-commit, and real-Compose workflow checks and record exact evidence.

Acceptance criteria:

- `npm run actionlint`, `npm run test:shell`, `npm run pre-commit`, and `git diff --check` pass.
- Required GitHub workflow checks pass for success and expected-failure fixtures.
- No mutable toolkit resolution or shell evaluation remains.
- No generated credentials, tokens, environment values, or unbounded raw logs enter outputs, summaries, or committed fixtures.
- Any deferred issue records rationale, owner, and residual risk.

## Dependency And Parallelization Guidance

| Wave | Tasks | Parallelism |
| --- | --- | --- |
| 1 | ACTBOX-01, ACTBOX-02 | Sequential around `action.yml` and wrapper contract; fake-binary test design may proceed while toolkit is implemented. |
| 2 | ACTBOX-03 | Starts after engine result-manifest behavior stabilizes. |
| 3 | ACTBOX-04 | Starts only after an exact toolkit version is published. |
| 4 | ACTBOX-05 | Independent and last. |

Shared hotspots are `compose-sandbox/action.yml`, `compose-sandbox/run.sh`, `tests/test-compose-sandbox.sh`, `package.json`, and the action README. Keep one owner at a time. Real Docker workflows must use unique Compose project names and artifact names per job.

Cross-repository dependency:

```text
CSBOX-02 -> ACTBOX-01
CSBOX-05 -> ACTBOX-03
CSBOX-07 + published version -> ACTBOX-04
ACTBOX-04 -> ACTBOX-05
```

## Deferred Decisions

- Consumer migrations are deferred to separate task files in `_database-tools` and `_vite-fastapi-postgres-template`.
- A reusable workflow is deferred because runner versions, checkout/ref evidence, tool installation, permissions, matrices, and test policy remain repository-specific.
- A shared binary-resolution shell library is deferred unless implementation proves it can improve both Compose and Confluence actions without changing either public contract.
- Supporting a user-provided multiline shell command is deliberately deferred; repository test commands belong in the toolkit's structured config.

ACTBOX-04 is blocked until CSBOX-07 identifies an exact published toolkit version. No maintainer decision blocks ACTBOX-01 design work.

## Toolkit Release Prerequisite (recorded by CSBOX-07 – 2026-08-25)

- Independent review completed in `repo-toolkit` at `projects/_repo-toolkit/docs/tasks/20260825-180040-compose-sandbox-runner.md` (Status: completed).
- Verified workspace state: `pnpm lint`/`typecheck`/`build`/`test` pass, `pnpm --filter @repo-toolkit/publish-packages test` passes (78 tests), `pnpm --filter @repo-toolkit/compose-sandbox test` passes (10 files, 134 tests), no tracked `dist/`, `git diff --check` passes; real-Compose fixtures skipped explicitly due to Docker unavailable in WSL (skip logic verified, requires GitHub-hosted Linux run for non-skipped proof).
- Current toolkit root version: `0.6.0` (`projects/_repo-toolkit/package.json`). `@repo-toolkit/compose-sandbox` is at `0.0.0-PLACEHOLDER` awaiting publish.
- Required publish step before ACTBOX-04/real-action CI: `pnpm release` (release-it bumps `VERSION` + root `package.json` via `.release-it.json`) then publish via `pnpm publish-packages -- --version <tag>` (e.g. `v0.7.0` or as decided) which rewrites placeholder to target version and publishes the tarball consumed by `release-artifact` asdf. ACTBOX-02/04 must pin the resulting exact version as `repo-toolkit-version` in `compose-sandbox/action.yml`.

## Definition Of Done

- All ACTBOX tasks are completed with verification evidence.
- `compose-sandbox` appears in the root module list and has complete input/output/security documentation.
- The action delegates all lifecycle behavior to the toolkit and contains no service-specific readiness or Compose teardown logic.
- Every remote dependency and toolkit installation is immutable or exact-versioned.
- Fake shell tests and real GitHub Compose tests cover success, failure, evidence, and no-leak behavior.
- Outputs and summaries are redacted, stable, and derived from the validated engine manifest.
- Separate consumer migration tasks can adopt the action without redesigning its public contract.
