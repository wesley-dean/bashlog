# AGENTS.md

This file is the concise operational map for contributors and AI-assisted tools.
It is intentionally smaller than the project's ADR corpus.  Architectural
reasoning belongs in `doc/adr/`; concise decision summaries belong in
`doc/decisions.md`; current observable behavior belongs in a project
specification when one exists; implementation-level contracts and rationale
belong beside the code in Doxygen comments.

## Start Here

Before consequential work:

1. Read `README.md` for the project overview and lifecycle.
2. Read `doc/decisions.md` for the concise architectural map and decision status.
3. Read the full ADRs governing the area you intend to change; use
   `doc/adr/README.md` as the index.
4. Read `doc/documentation-standard.md` before editing Bash source comments.
5. Read `doc/testing.md` before changing tests or generated artifacts.
6. Read `doc/release-verification.md` before changing release behavior.

`doc/decisions.md` is a discovery aid, not a replacement for the governing ADR.
When reasoning, rejected alternatives, security boundaries, or consequences
matter, read the full record.

When repository evidence and an ADR conflict, surface the conflict.  Do not
silently treat the implementation as the architectural source of truth.

Proposed ADRs are proposals rather than binding current architecture.  Do not
silently implement a proposed decision as though it were accepted; resolve its
status as part of the consequential change that depends on it.

## Repository Shape

- `src/`: entrypoint and product-facing orchestration inherited from the starter;
  bashlog's sourceable-library entry behavior is being defined by project ADRs.
- `lib/`: maintained reusable implementation modules.
- `lib/plugins/`: automatically discovered additive modules under the current
  starter architecture; ADR-016 proposes specializing this model for bashlog.
- `tests/`: Bats behavior tests and Bash compatibility helpers.
- `doc/decisions.md`: concise architectural decision summaries and ADR links.
- `doc/adr/`: architectural decision records and their full reasoning.
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

## Source and Module Architecture

The inherited starter currently assembles a release artifact from an explicit
core source order plus lexically sorted files under `lib/plugins/`.  ADR-016
proposes retaining explicit core ordering and deterministic additive-module
discovery while removing the starter's runtime plugin registry and noop plugin
for bashlog.

Until the proposed ADR is accepted and implemented, distinguish current repository
shape from intended bashlog architecture.  Do not introduce additional runtime
plugin-registry dependencies merely because the scaffold currently contains one.

See ADR-004 and proposed ADR-016.

## Documentation Standard

Bash source is documentation-first and intentionally verbose.  Doxygen comments
are architecture at implementation scope, not decorative prose.

The exact source documentation syntax is mandatory and compatible with the
`bash-doxygen` tooling used across the related project family:

- Doxygen comment lines begin with `##`.
- Files use `@file`, `@brief`, and substantive `@details` blocks.
- Significant functions use `@fn`, `@brief`, `@details`, parameters, output and
  return semantics, and examples as applicable.
- Significant documented variables use `@var` where appropriate.
- Documentation blocks remain contiguous with the declarations they document so
  `bash-doxygen` can associate and validate them.

Do not substitute a merely similar Doxygen comment syntax.  The structure is a
project requirement, not a style suggestion.

Do not reduce documentation merely to make maintained source shorter.  The
ordinary and minified consumer artifacts remove or compress comment-only source;
the `.dev.bash` artifact intentionally retains the maintenance narrative.

Security-sensitive helpers require substantive documentation even when they are
internal.  Explain quoting assumptions, matcher semantics, ordering, failure
behavior, and security boundaries that a reviewer would otherwise need to infer.

See ADR-007, ADR-008, ADR-019, and `doc/documentation-standard.md`.

## Security-Sensitive Work

Redaction architecture is being defined in proposed ADR-018.  Work in that area
must preserve the distinction between accepted and proposed decisions and should
not allow implementation experiments to silently choose unresolved semantics.

In particular, open questions around redaction contexts, fixed/glob/ERE matching,
zero-length regular expressions, rule ordering, context lifecycle, and final
fixed-secret verification belong in ADRs before they become stable behavior.

The project explicitly rejects vague trust claims and security through obscurity.
Read the full redaction and auditability ADRs before implementing the
security-critical output path.

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

Security-sensitive behavior should use negative tests as well as positive tests.
For example, future redaction tests should verify not only that the replacement is
present but also that protected original values do not appear in stdout, stderr,
or failure diagnostics.

## Scope Discipline

Prefer the smallest coherent change that satisfies the governing decision.  Do
not mix unrelated cleanup into functional work.  Record useful but orthogonal
ideas separately rather than expanding scope without acknowledgment.

When changing architecture, update or add an ADR before or with the
implementation.  Update `doc/decisions.md` when the operative decision changes.
After implementation, compare the result back against the same ADR constraints
to catch locally-correct architectural drift.
