# Bash Starter Repository

This repository is a starter for maintainable, documented, tested, and
releasable Bash projects.  It consolidates engineering patterns proven across
adrctl, bashdeps, Bootstrap, and mktext while keeping the starter small enough to
adapt rather than turning it into a framework.

The maintained source is modular.  `make build` assembles that source into three
standalone consumer representations, and plugins under `lib/plugins/` are
automatically discovered in deterministic lexical order.  The included noop
plugin is both executable starter behavior and a reference implementation for
future extension.

## Adapt the Starter

A new project should normally begin by changing `PROJECT_NAME` in the Makefile,
replacing the example CLI and noop behavior as appropriate, and reviewing the
starter ADRs to decide which decisions remain applicable.  `PROJECT_NAME` must
be one non-empty whitespace-free word; conventional names such as `my-tool`,
`my_tool`, or `my.tool` keep generated filenames and Make targets predictable.
Maintained Bash source filenames, including plugin filenames under
`lib/plugins/`, must also be whitespace-free as documented by ADR-004.

The CI and release workflows discover generated Bash artifacts from `dist/`
rather than hard-code `template-bash`, so changing `PROJECT_NAME` does not
require corresponding artifact-name edits in those workflows.

Delete starter behavior that does not belong in the derived project; do not
preserve it merely because it came from the template.  The template intentionally
provides starter files rather than placeholder-only empty directories.

## Build Lifecycle

The canonical orchestration interface is Make:

- `make deps` synchronizes repository dependencies and may use the network.
- `make deps-check` verifies prepared dependency state offline.
- `make build` creates release artifacts from maintained source and prepared
  dependencies without synchronizing dependencies.
- `make all` runs `deps` and then `build`, so it may use the network.
- `make check` runs Bash syntax validation and ShellCheck.
- `make format` runs shfmt with `-i 2 -bn -ci -sr -kp`.
- `make test` runs Bats against every artifact flavor.
- `make test-report` writes JUnit reports under `test-results/`.
- `make docs` generates Doxygen HTML under `doc/reference/` from prepared
  dependency state.
- `make clean` removes build, test-report, and reference-documentation output.
- `make distclean` additionally removes prepared repository dependencies.

Repository dependencies are scripts, libraries, filters, and assets.  bashdeps
does not install system tools or operating-system packages.  The Makefile
bootstraps only bashdeps directly; bashdeps manages Bash-Minifier and the
bash-doxygen filter through `dependencies.txt`.

## Release Artifacts

For the default project name, `make build` produces:

```text
dist/template-bash.dev.bash
dist/template-bash.dev.bash.sha256
dist/template-bash.bash
dist/template-bash.bash.sha256
dist/template-bash.min.bash
dist/template-bash.min.bash.sha256
```

The `.sha256` files use conventional SHA-256 checksum-file syntax.  New builds
and releases publish only `.sha256` checksum companions.  Historical releases
that contain `.256` companions remain valid for those release versions; consumers
that automate across release generations should prefer `.sha256` and use `.256`
only when the preferred companion is confirmed absent.

The development artifact retains the verbose Doxygen commentary used for
maintenance.  The ordinary artifact removes full-line comments while preserving
the shebang and behavior.  The minified artifact is derived from the ordinary
artifact with the pinned Bash-Minifier dependency.  All three include executable
version, build-date, and build-commit provenance and are expected to satisfy the
same behavior tests.

For reproducibility, the default build date comes from the current Git commit
rather than the wall clock.  Local builds made while maintained source is dirty
mark the build commit with a `-dirty` suffix so generated provenance does not
imply that modified bytes came solely from the named commit.

## Documentation and Architectural Decisions

This project deliberately treats documentation as part of the engineering
architecture.  Bash source follows the normative Doxygen standard in
`doc/documentation-standard.md`, with a "more is more" posture toward preserving
contracts, assumptions, failure semantics, examples, and reasoning.

ADRs under `doc/adr/` preserve durable architectural reasoning, alternatives,
tradeoffs, consequences, and operational constraints.  `AGENTS.md` is a concise
operational map that points back to those source decisions rather than becoming
a second architecture manual.  Generated Doxygen output is written to
`doc/reference/` and is not committed.

ADR-012 defines the current `.sha256` checksum companion naming and historical
`.256` read-compatibility policy.

See `doc/adr/README.md` for the ADR index.

## Testing

Bats tests live under `tests/` and are intentionally behavior-oriented.  The
starter tests its example help/version interface, plugin discovery and dispatch,
artifact executability, checksum companions, and invalid input behavior.  A
derived project should add focused tests for its real contracts rather than grow
a few oversized fixtures.

The default compatibility floor is Bash 4.3.  Release CI should validate
representative behavior under that version in addition to the primary runner.

## Releases and Conventional Commits

The release workflow uses Conventional Commits with
`bitshifted/git-auto-semver`.  `feat` increments the minor version,
`BREAKING CHANGE` increments the major version, and supported maintenance commit
types increment the patch version.  The workflow calculates the version without
creating a tag, validates and attests the exact release artifacts, and creates
the release/tag only after validation succeeds.

## Existing Repository Tooling

The upstream template's MegaLinter, CodeQL, Scorecard, Dependabot, issue
management, and related configuration is intentionally retained unless it
conflicts with the Bash build architecture.  Projects may tune those controls to
match repository visibility and available GitHub features.

## License and Contributions

This project is dedicated to the public domain under CC0 1.0 Universal.  See
`LICENSE` and `CONTRIBUTING.md` for details, and `CODE_OF_CONDUCT.md` for the
project's expectations for respectful collaboration.
