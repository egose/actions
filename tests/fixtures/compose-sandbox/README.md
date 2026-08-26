# compose-sandbox fixtures

Minimal real-Compose fixtures for GitHub-hosted integration tests.

- `docker-compose.yml` – long-running `web` (nginx:alpine) + successful one-shot `init` (alpine:3.18)
- `success.mjs` – HTTP + service-completed readiness, `node -e process.exit(0)` test, evidence `always`
- `failure.mjs` – same topology but `node -e process.exit(2)` forces test failure to exercise artifact upload and cleanup

Both fixtures use distinct `projectName` values (`cs-test-success`, `cs-test-failure`) and bounded timeouts (60s startup/readiness, 30s test/cleanup) so parallel jobs do not leak containers/networks.

The workflow `test-compose-sandbox.yml` exercises both success and forced-failure paths through `uses: ./compose-sandbox` with the exact published `@repo-toolkit/compose-sandbox@0.18.0`.

Consumer-shaped references:

- Database-shaped mixed probes (TCP/HTTP/one-shot + Bats) and template-shaped HTTP probes (Playwright) are documented in `compose-sandbox/README.md` and the engine docs; these fixtures prove the thin-wrapper + engine contract without requiring those full consumer repos.
