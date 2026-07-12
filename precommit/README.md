# Run and Handle Pre-Commit

`precommit` is a compatibility wrapper that delegates to [`pre-commit`](../pre-commit/README.md).

New usage should prefer:

```yaml
uses: egose/actions/pre-commit@main
```

Existing `egose/actions/precommit@main` workflows continue to work and delegate to the canonical action.
