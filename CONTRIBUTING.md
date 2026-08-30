# Contributing

Contributions are welcome.  bashlog is intentionally small, documentation-first,
and conservative about expanding its public surface, so changes should preserve
that posture rather than treating the repository as a generic Bash utility.

Before making a consequential change, please read:

- `README.md` for the project contract and current behavior;
- `doc/engineering-philosophy.md` for the reusable design posture behind the
  project;
- `AGENTS.md` for the contributor-oriented repository map;
- `doc/decisions.md` and the governing ADRs under `doc/adr/`;
- `doc/bashlog-spec.md` before changing observable public behavior;
- `doc/threat-model.md` before changing trust boundaries, sensitive-data flow,
  dependencies, output sinks, or other security-relevant behavior;
- `doc/documentation-standard.md` before editing maintained Bash comments;
- `doc/testing.md` before changing the behavior contract; and
- `doc/release-verification.md` before changing release behavior.

## Development Expectations

Prefer focused changes with a clear contract.  Consequential architectural work
should update or add an ADR.  Observable public behavior changes should keep the
specification, Doxygen contracts, tests, README, and implementation consistent.

The engineering philosophy is guidance rather than a replacement for governing
ADRs.  When a concrete Accepted decision exists, the ADR remains authoritative.

The canonical validation surfaces are:

```text
make check
make test
make test-report
make adr-index
make docs
make deps-check
```

Generated files under `dist/`, `doc/reference/`, `test-results/`, and `vendor/`
are not maintained source and should not be edited directly.  The committed
`doc/adr/README.md` is also generated, but intentionally remains in Git because it
is the ADR directory's GitHub landing page.  Change its stable framing through
`doc/adr/README.intro.md` or `doc/adr/README.outro.md`, change ADR titles in the
ADR files themselves, then regenerate with `make adr-index`.

Public API additions are compatibility commitments.  Please avoid exposing an
internal helper merely because doing so would make one implementation task more
convenient.

Security-sensitive changes deserve explicit threat-model review and negative tests
as well as positive ones.  For example, a redaction test should prove that
protected input does not appear in any bashlog-controlled observable output, not
only that the expected replacement is present.

Every new dependency should be treated as an expansion of the trusted computing
base.  Pinning and checksum verification establish acquisition integrity, not a
proof that the dependency is behaviorally safe or appropriately trusted with the
data and authority bashlog would provide it.

## Reporting Problems

Use `SUPPORT.md` for ordinary support and bug-report guidance.  Suspected
vulnerabilities should be reported according to `SECURITY.md` rather than in a
public issue.

## Collaboration Policy

Contributors are expected to follow `CODE_OF_CONDUCT.md`.

## Public Domain

This project is dedicated to the public domain within the United States, and
copyright and related rights in the work worldwide are waived through the
[CC0 1.0 Universal public domain dedication](https://creativecommons.org/publicdomain/zero/1.0/).

See [`LICENSE`](LICENSE) for the repository's license text.  By contributing, you
agree that your contribution will be released under the same CC0 dedication.
