<!-- Keep the PR title brief, descriptive, and suitable for a changelog entry. -->
<!-- Link an issue when one exists. -->

## Summary

Describe the problem and the change at a level a reviewer can understand without
reconstructing intent from the diff.

## Contract / Architecture Impact

- [ ] No observable public behavior or architectural decision changes.
- [ ] `doc/bashlog-spec.md` is updated when observable public behavior changes.
- [ ] Governing ADRs are updated or added when architectural intent changes.
- [ ] `doc/decisions.md`, `AGENTS.md`, and README are updated where their summaries
      would otherwise become stale.

## Implementation and Documentation

- [ ] Maintained Bash uses the project Doxygen standard.
- [ ] Public function documentation agrees with the normative specification.
- [ ] Generated files under `dist/`, `doc/reference/`, `test-results/`, and
      `vendor/` were not edited directly.

## Validation

- [ ] Focused tests cover the new or changed behavior.
- [ ] Security-sensitive changes include negative assertions where applicable.
- [ ] All three generated artifact flavors remain behaviorally equivalent.
- [ ] Bash 4.3 compatibility remains intact or the runtime-floor decision is
      explicitly revisited.
- [ ] Relevant project validation has been run (`make check`, `make test`,
      `make test-report`, `make docs`, and/or `make deps-check`).

## Additional Notes

Document tradeoffs, deferred work, compatibility concerns, or reviewer context
that does not belong in maintained project documentation.
