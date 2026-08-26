export default {
  cwd: '.',
  compose: {
    files: ['docker-compose.yml'],
    projectName: 'cs-test-failure',
  },
  readiness: [
    { type: 'http', url: 'http://127.0.0.1:8000/' },
    { type: 'service-completed', service: 'init' },
  ],
  test: { executable: 'node', args: ['-e', 'process.exit(2)'] },
  evidence: { directory: '.compose-sandbox-logs', capture: 'always' },
  cleanup: { volumes: true, removeOrphans: true },
  timeouts: { startupMs: 60000, readinessMs: 60000, testMs: 30000, cleanupMs: 30000 },
};
