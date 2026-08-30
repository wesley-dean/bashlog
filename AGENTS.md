# AGENTS.md

This file is the concise operational map for contributors and AI-assisted tools.
It is intentionally smaller than the project's ADR corpus.  Architectural
reasoning belongs in `doc/adr/`; concise decision summaries belong in
`doc/decisions.md`; normative public behavior belongs in `doc/bashlog-spec.md`;
implementation-level contracts and rationale belong beside the code in Doxygen
comments.

## Start Here

Before consequential work:

1. Read `README.md` for the public project contract and current project status.
2. Read `doc/decisions.md` for the concise architectural map and decision status.
3. Read the full ADRs governing the area you intend to change; use
   `doc/adr/README.md` as the index.
4. Read `doc/bashlog-spec.md` before changing public behavior or implementing the
   proposed API.  The specification is currently Draft while ADR-013 through
   ADR-024 remain Proposed.
5. Read `doc/documentation-standard.md` before editing Bash source comments.
6. Read `doc/testing.md` before changing tests or generated artifacts.
7. Read `doc/release-verification.md` before changing release behavior.

`doc/decisions.md` is a discovery aid, not a replacement for the governing ADR.
When reasoning, rejected alternatives, security boundaries, or consequences
matter, read the full record.

`doc/bashlog-spec.md` defines the proposed observable contract.  It does not
supersede a governing ADR.  When the specification and an ADR conflict, surface
the conflict and correct the documents before implementation rather than choosing
whichever text is more convenient.

When repository evidence and an ADR conflict, surface the conflict.  Do not
silently treat the implementation as the architectural source of truth.

Proposed ADRs are proposals rather than binding current architecture.  Do not
silently implement a proposed decision as though it were accepted; resolve its
status as part of the consequential change that depends on it.

## Repository Shape

- `src/`: starter-derived entrypoint/orchestration that has not yet been replaced
  by bashlog's sourceable-library implementation.
- `lib/`: maintained reusable implementation modules.
- `lib/plugins/`: starter-derived additive-module layout; ADR-016 proposes
  retaining deterministic modular assembly while removing runtime plugin-registry
  semantics.
- `tests/`: Bats behavior tests and Bash compatibility helpers.
- `doc/bashlog-spec.md`: Draft normative public behavior specification.
- `doc/decisions.md`: concise architectural decision summaries and ADR links.
- `doc/adr/`: architectural decision records and their full reasoning.
- `doc/reference/`: generated Doxygen output; never commit it.
- `vendor/`: generated dependency state managed by bashdeps; never commit it.
- `dist/`: generated release artifacts; never edit them directly.
- `test-results/`: generated JUnit reports.

The repository still contains implementation scaffolding inherited from
`template-bash`.  Documentation of intended bashlog behavior must not be mistaken
for evidence that the starter runtime already implements that behavior.

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

The current Makefile still uses the starter project name and starter source
assembly.  The intended first-release bashlog artifacts described in the README
and specification remain planned behavior until implementation updates the build.

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

## Public API Direction

The Draft specification proposes this initial public surface:

```text
bashlog_level_get
bashlog_level_set

bashlog_log
bashlog_debug
bashlog_info
bashlog_notice
bashlog_warning
bashlog_error
bashlog_critical
bashlog_alert
bashlog_emergency

bashlog_redaction_add
bashlog_redaction_context_destroy
bashlog_redact
```

Important proposed public semantics include:

- Bash 4.3 remains the minimum runtime.
- The default logging threshold is `info`.
- Canonical severity names are full names rather than short aliases.
- All routine logging is written to standard error; standard output remains an
  application data channel.
- `bashlog_redact` is a transform-only API that writes successful output to
  standard output without adding a newline.
- Logging calls select redaction explicitly with `--context CONTEXT`; there is no
  ambient current context.
- The initial renderer is `LEVEL: MESSAGE` with lowercase canonical severity.
- Timestamps, colors, tags, automatic environment metadata, file-descriptor
  selection, syslog, network sinks, and `bashlog_die` are intentionally outside
  the initial public contract.
- Shared public return statuses are documented in `doc/bashlog-spec.md` and must
  be reflected exactly in Doxygen blocks and tests.

Do not expand this public surface during implementation merely because a helper is
convenient to expose.  New public functions are compatibility commitments and
must be documented deliberately.

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

Public-function Doxygen documentation must agree with `doc/bashlog-spec.md` on
arguments, outputs, statuses, and failure behavior.  A disagreement is a defect to
investigate, not an instruction to rewrite whichever document is easiest.

See ADR-007, ADR-008, ADR-019, `doc/documentation-standard.md`, and
`doc/bashlog-spec.md`.

## Security-Sensitive Work

ADR-018 proposes the overarching redaction security boundary.  ADR-020 through
ADR-024 propose the concrete context, rule, matcher, and final-verification
semantics that refine it.  Work in this area must preserve the distinction
between accepted and proposed decisions and must not let implementation
experiments silently choose different behavior.

The proposed redaction model includes the following review-critical properties:

- contexts follow an `unseen -> active -> destroyed` lifecycle and are append-only
  while active;
- an explicitly requested unknown or destroyed context fails closed;
- rules explicitly name `fixed`, `glob`, or `ere` and retain registration order;
- duplicate matcher/pattern pairs are rejected rather than treated as updates;
- replacement text is always literal, and empty replacement is permitted;
- `fixed` provides exact literal multibyte matching without Unicode normalization;
- glob and ERE patterns that can match empty text are rejected;
- extglob is not part of the initial glob contract;
- ERE uses Bash `[[ =~ ]]` semantics and invalid EREs are rejected;
- one ordered transformation pass is followed by non-transforming final
  verification against every active rule;
- any remaining match or verification error suppresses output rather than
  triggering iterative rewriting;
- and redaction failure diagnostics use a bounded path that never reproduces the
  failed candidate or protected rule content.

The Draft specification further fixes the public failure diagnostic candidate as:

```text
bashlog: message suppressed
```

When an active rule set is available, that diagnostic must itself pass final
verification or remain silent.

The project explicitly rejects vague trust claims and security through obscurity.
Read ADR-018 through ADR-024, ADR-019, and the Draft specification before
implementing the security-critical output path.

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
For redaction, tests should verify not only that the expected replacement is
present but also that protected originals do not appear in stdout, stderr,
failure diagnostics, or other observable bashlog sink output.  Cross-rule tests
should include cases where later replacements reintroduce text protected by
earlier fixed, glob, or ERE rules and verify fail-closed suppression.

The Draft specification contains a concrete list of required test implications.
Treat that list as the starting behavior matrix for the next implementation
phase rather than inventing test semantics from source code.

## Scope Discipline

Prefer the smallest coherent change that satisfies the governing decision.  Do
not mix unrelated cleanup into functional work.  Record useful but orthogonal
ideas separately rather than expanding scope without acknowledgment.

When changing architecture, update or add an ADR before or with the
implementation.  Update `doc/decisions.md` when the operative decision changes.
When changing observable public behavior, update `doc/bashlog-spec.md` before or
with the implementation and corresponding Doxygen/tests.  After implementation,
compare the result back against the same ADR constraints to catch locally-correct
architectural drift.
