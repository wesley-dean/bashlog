# AGENTS.md

This file is the concise operational map for contributors and AI-assisted tools.
It is intentionally smaller than the project's ADR corpus.  Architectural
reasoning belongs in `doc/adr/`; current observable behavior belongs in a
project specification when one exists; implementation-level contracts and
rationale belong beside the code in Doxygen comments.

## Start Here

Before consequential work:

1. Read `README.md` for the project overview and lifecycle.
2. Read the ADR index in `doc/adr/README.md` and the ADRs governing the area you
   intend to change.
3. Read `doc/documentation-standard.md` before editing Bash source comments.
4. Read `doc/testing.md` before changing tests or generated artifacts.
5. Read `doc/release-verification.md` before changing release behavior.

When repository evidence and an ADR conflict, surface the conflict.  Do not
silently treat the implementation as the architectural source of truth.

## Repository Shape

- `src/`: entrypoint and product-facing orchestration.
- `lib/`: maintained reusable implementation modules.
- `lib/plugins/`: automatically discovered plugin modules.
- `tests/`: Bats behavior tests and Bash compatibility helpers.
- `doc/adr/`: architectural decision records and their reasoning.
- `doc/reference/`: generated Doxygen output; never commit it.
- `vendor/`: generated dependency state managed by bashdeps; never commit it.
- `dist/`: generated release artifacts; never edit them directly.
- `test-results/`: generated JUnit reports.

## Build and Dependency Boundaries

`make` is the canonical local and CI orchestration interface.

- `make deps` may access the network and may repair script/library/asset
  dependency state.
- `make deps-check` is offline and verifies prepared dependency state.
- `make build` is offline and consumes prepared dependency state.
- `make all` runs `deps` and then `build`, so `all` may use the network.
- `make docs` is offline and consumes the prepared Doxygen filter.
- bashdeps manages repository dependencies such as scripts, libraries, and
  assets.  It does not install system tools or operating-system packages.

See ADR-003 and ADR-005 for the governing dependency and orchestration decisions.
See ADR-006 and ADR-012 for the release-artifact and checksum-companion contract.

## Source and Plugin Architecture

The release artifact is assembled from an explicit core source order plus
lexically sorted files under `lib/plugins/`.  Plugin files register themselves
through the plugin registry and should not require edits to a central dispatcher
merely to become discoverable.

The noop plugin is the reference implementation for a minimal plugin.  Prefer
copying and adapting that contract over adding platform-specific conditionals to
unrelated core modules.

See ADR-004.

## Documentation Standard

Bash source is documentation-first and intentionally verbose.  Doxygen comments
are architecture at implementation scope, not decorative prose.  Every Doxygen
comment line begins with `##`.  File and function blocks should explain intent,
contracts, assumptions, failure behavior, and examples with enough detail that a
future maintainer can recover reasoning without guessing from code alone.

Do not reduce documentation merely to make maintained source shorter.  The
standard and minified consumer artifacts remove comment-only lines; the
`.dev.bash` artifact intentionally retains them.

See ADR-007, ADR-008, and `doc/documentation-standard.md`.

## Validation

Use the smallest relevant set first, then the full project contract:

- `make check`
- `make test`
- `make test-report`
- `make docs`
- `make deps-check`

`make check` performs Bash syntax validation and ShellCheck against maintained
Bash files.  `make format` uses the same shfmt arguments as MegaLinter:
`-i 2 -bn -ci -sr -kp`.

Behavior tests must exercise every shipped artifact flavor.  Generated release
artifacts are public products and must not depend on `vendor/` at runtime.  Every
current executable artifact must have a valid adjacent `.sha256` checksum
companion, and a successful build must not retain a stale `.256` companion for
the same artifact.

## Scope Discipline

Prefer the smallest coherent change that satisfies the governing decision.  Do
not mix unrelated cleanup into functional work.  Record useful but orthogonal
ideas separately rather than expanding scope without acknowledgment.

When changing architecture, update or add an ADR before or with the
implementation.  After implementation, compare the result back against the
same ADR constraints to catch locally-correct architectural drift.
