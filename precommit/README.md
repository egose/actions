# Run and Handle Pre-Commit

`precommit` remains available as a compatibility wrapper around [`pre-commit`](../pre-commit/README.md).

New usage should prefer:

```yaml
uses: egose/actions/pre-commit@main
```

Existing `egose/actions/precommit@main` workflows continue to work and delegate to the renamed action.
