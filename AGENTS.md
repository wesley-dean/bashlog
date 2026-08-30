# AGENTS.md

This file is the concise operational map for contributors and AI-assisted tools.
It is intentionally smaller than the project's ADR corpus.  Reusable engineering
posture belongs in `doc/engineering-philosophy.md`; architectural reasoning
belongs in `doc/adr/`; concise decision summaries belong in `doc/decisions.md`;
normative public behavior belongs in `doc/bashlog-spec.md`; explicit security
analysis belongs in `doc/threat-model.md`; implementation-level contracts and
rationale belong beside the code in exact `bash-doxygen`-compatible Doxygen
comments.

## Start Here

Before consequential work:

1. Read `README.md` for the public project contract and current project status.
2. Read `doc/engineering-philosophy.md` for the reusable engineering posture that
   informs areas not already governed by a more specific Accepted ADR.
3. Read `doc/decisions.md` for the concise architectural map.
4. Read the full ADRs governing the area you intend to change; use
   `doc/adr/README.md` as the index.
5. Read `doc/bashlog-spec.md` before changing public behavior.  The specification
   is the Accepted normative public contract.
6. Read `doc/threat-model.md` before changing dependencies, sensitive-data flow,
   output sinks, trust boundaries, matcher behavior, redaction semantics, or other
   security-relevant behavior.
7. Read `doc/documentation-standard.md` before editing Bash source comments.
8. Read `doc/testing.md` before changing tests or generated artifacts.
9. Read `doc/release-verification.md` before changing release behavior.

`doc/engineering-philosophy.md` is guidance rather than a replacement for a
governing ADR.  `doc/decisions.md` is a discovery aid, not a replacement for the
governing ADR.  When reasoning, rejected alternatives, security boundaries, or
consequences matter, read the full record.

`doc/bashlog-spec.md` defines observable public behavior.  It does not supersede
a governing ADR.  When the specification, implementation, tests, and an Accepted
ADR disagree, surface the conflict and correct the appropriate source rather than
silently choosing whichever artifact is easiest to change.

`doc/threat-model.md` consolidates the project's current security objectives,
assets, trusted computing base, trust boundaries, threats, mitigations, evidence,
residual risks, and review triggers.  It does not replace the security decisions
recorded in ADRs or the public contract defined by the specification.

## Repository Shape

- `lib/level.bash`: severity normalization and process-local threshold state.
- `lib/redaction-core.bash`: internal redaction state, matcher algorithms,
  transformation, final verification, and safe diagnostic handling.
- `lib/redaction.bash`: public redaction registration, context destruction, and
  transform-only redaction API.
- `lib/presentation.bash`: renderer selection, Bash-native timestamps, tag
  validation, logfmt encoding, global color policy, per-severity token styles,
  and human/logfmt rendering.
- `lib/logging.bash`: generic logger, canonical severity helpers, logging option
  parsing, redaction/presentation ordering, and standard-error emission.
- `tests/contract/`: active Bats public behavior and security contract.
- `tests/contract/compat-bash43.bash`: representative Bash 4.3 compatibility
  contract executed against every generated artifact.
- `doc/engineering-philosophy.md`: reusable engineering posture and design
  principles.
- `doc/bashlog-spec.md`: Accepted normative public behavior specification.
- `doc/decisions.md`: concise architectural decision summaries and ADR links.
- `doc/adr/`: Accepted architectural decision records and their full reasoning.
- `doc/threat-model.md`: maintained threat model and Mermaid trust-boundary/data-
  flow diagram.
- `doc/reference/`: generated Doxygen output; never commit it.
- `vendor/`: generated dependency state managed by bashdeps; never commit it.
- `dist/`: generated release artifacts; never edit them directly.
- `test-results/`: generated JUnit reports.

The inherited starter CLI, runtime plugin registry, noop plugin, and starter-only
behavior tests have been removed.  bashlog is assembled as a sourceable library,
not as a command dispatcher.

## Build and Dependency Boundaries

`make` is the canonical local and CI orchestration interface.

- `make deps` may access the network and may repair repository dependency state.
- `make deps-check` is offline and verifies prepared dependency state.
- `make build` is offline and consumes prepared dependency state.
- `make all` runs dependency convergence and then builds, so it may use the
  network through `deps`.
- `make check` performs maintained-source Bash syntax validation and ShellCheck.
- `make format` uses the project shfmt policy.
- `make test` builds and runs the active Bats contract against every artifact.
- `make test-report` repeats the artifact matrix and writes JUnit XML under
  `test-results/`.
- `make docs` is offline and consumes the prepared `bash-doxygen` filter.

bashdeps manages repository dependencies such as scripts, filters, and assets.  It
does not install system tools or operating-system packages.

Every dependency expands the trusted computing base.  Pinning and checksum
verification establish expected acquisition bytes; they do not prove behavioral
safety or justify the authority and data a dependency receives.  Dependency
changes should be reviewed against `doc/threat-model.md`, including runtime,
build, CI, documentation, and release tooling according to their authority.

The maintained source order is explicit:

```text
lib/level.bash
lib/redaction-core.bash
lib/redaction.bash
lib/presentation.bash
lib/logging.bash
```

The build produces:

```text
dist/bashlog.dev.bash
dist/bashlog.dev.bash.sha256
dist/bashlog.bash
dist/bashlog.bash.sha256
dist/bashlog.min.bash
dist/bashlog.min.bash.sha256
```

The three executable artifacts must exhibit equivalent public behavior and must
remain usable after `vendor/` is removed.  `.sha256` is the current checksum
companion extension; successful builds must not leave stale `.256` companions for
current artifacts.

See ADR-003, ADR-005, ADR-006, ADR-012, and ADR-016.

## Public API Contract

The Accepted public surface is:

```text
bashlog_level_get
bashlog_level_set

bashlog_format_get
bashlog_format_set
bashlog_timestamp_get
bashlog_timestamp_set
bashlog_color_get
bashlog_color_set
bashlog_level_style_get
bashlog_level_style_set
bashlog_level_style_reset

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

Important public semantics include:

- Bash 4.3 is the minimum runtime.
- Runtime library behavior uses Bash language facilities and builtins only; it
  invokes no external commands.
- The default logging threshold is `info`.
- Canonical severity names are full names rather than short aliases.
- Routine logging goes to standard error; standard output remains an application
  data channel.
- `bashlog_redact` writes successful transformed output to standard output without
  adding a newline.
- Logging calls select redaction explicitly with `--context CONTEXT`; there is no
  ambient current context and registered contexts remain inert until invoked.
- Callers may alternatively invoke `bashlog_redact` themselves before ordinary
  logging; both redaction workflows are first-class public behavior.
- `--` terminates bashlog logging-option parsing when a format string could be
  interpreted as an option.
- The default format mode is `auto`: TTY stderr selects human rendering and
  non-TTY stderr selects deterministic logfmt.
- Timestamp mode defaults to `off`; `utc` and `local` use Bash-native time
  formatting without external `date`.
- Color mode defaults to `auto`; `never|auto|always` decides whether human
  severity styling may be emitted.
- bashlog-owned style applies only to the canonical severity token and resets
  immediately after that token.  Timestamp, tags, punctuation, and message text
  remain outside the style span.
- Per-level style is symbolic and configurable with foreground color plus
  `normal|bold|dim`; raw ANSI/SGR input is not accepted.
- Default styles are emergency/alert/critical bold red, error red, warning
  yellow, notice cyan, info green, and debug dim in the terminal default
  foreground.
- The logfmt renderer never contains bashlog-owned ANSI regardless of color or
  per-level style configuration.
- Repeatable `--tag TAG` metadata uses the documented ASCII token grammar and
  preserves caller order.
- Automatic host/deployment metadata, caller-selected file descriptors, syslog,
  network sinks, and `bashlog_die` remain outside the contract.
- Shared public return statuses are defined in `doc/bashlog-spec.md`.

Do not expand the public surface merely because an internal helper is convenient
to expose.  New public functions are compatibility commitments and require
intentional specification, documentation, tests, and architectural review where
appropriate.

See ADR-025, ADR-026, ADR-027, and `doc/bashlog-spec.md` for presentation details.

## Documentation Standard

Bash source is documentation-first and intentionally verbose.  Doxygen comments
are architecture at implementation scope, not decorative prose.

The exact syntax is mandatory and compatible with `bash-doxygen`:

- Doxygen comment lines begin with `##`.
- Files use `@file`, `@brief`, and substantive `@details` blocks.
- Significant functions use `@fn`, `@brief`, `@details`, named `@param` entries,
  output behavior, return statuses, examples, warnings, and references as
  applicable.
- Significant documented variables use `@var` where appropriate.
- Structural comment blocks remain contiguous with the declaration they document
  so `bash-doxygen` can associate and validate them correctly.

Do not substitute a merely similar comment style.  The structure is a project
requirement.

Do not reduce maintained-source documentation merely to make source shorter.  The
ordinary and minified artifacts remove or compress comment-only source, while
`bashlog.dev.bash` intentionally preserves the maintenance narrative.

Security-sensitive internal helpers require substantive comments.  Explain
matcher progression, quoting, shell-option interactions, ordering, failure
behavior, process/runtime limitations, and any non-obvious Bash semantics that a
reviewer would otherwise need to reconstruct.

Public-function Doxygen documentation must agree with `doc/bashlog-spec.md` on
arguments, streams, statuses, and failure behavior.  A disagreement is a defect
to investigate, not an instruction to rewrite whichever document is easiest.

See ADR-007, ADR-008, ADR-019, and `doc/documentation-standard.md`.

## Security-Sensitive Work

ADR-018 governs the overarching redaction security boundary.  ADR-020 through
ADR-024 govern context lifecycle, rule registration, matcher semantics, and the
final fail-closed output boundary.  ADR-026 defines the semantic-data-before-
presentation ordering for logger-managed redaction.  `doc/threat-model.md`
consolidates those decisions with the project's broader assets, trust boundaries,
dependency and supply-chain considerations, downstream rendering risks, and
residual non-promises.

Review-critical properties include:

- contexts follow `unseen -> active -> destroyed` and are append-only while
  active;
- an explicitly requested unknown or destroyed context fails closed;
- rules explicitly name `fixed`, `glob`, or `ere` and preserve successful
  registration order;
- duplicate matcher/pattern pairs are rejected rather than treated as updates;
- replacement text is always literal, and empty replacement is permitted;
- `fixed` provides exact literal multibyte matching without Unicode
  normalization;
- glob and ERE patterns capable of matching empty text are rejected;
- extglob is outside the initial glob contract;
- ERE uses Bash `[[ =~ ]]` semantics and invalid EREs are rejected;
- one ordered transformation pass is followed by non-transforming verification;
- logger-managed primary redaction operates on the fully formatted message and
  each caller-supplied tag before renderer quoting, punctuation, or ANSI styling;
- a context-protected completed record receives final non-transforming
  verification after rendering and before stderr emission;
- any remaining match or verification error suppresses output rather than
  triggering iterative rewriting;
- the only redaction-failure diagnostic candidate is
  `bashlog: message suppressed`, and it must itself satisfy active policy before
  emission;
- no public operation returns secret-bearing registered rules;
- context destruction is not secure memory erasure;
- caller-side xtrace can expose expanded arguments before bashlog gains control.

Changes that add dependencies, alter data-egress behavior, expand output sinks,
change sensitive-data interpretation, or move trust boundaries should revisit the
threat model even when the redaction algorithms themselves are unchanged.

### Presentation Boundary

Presentation is downstream of primary redaction.  Human punctuation, logfmt
serialization, and ANSI severity styling must never become mechanisms by which
bashlog discovers sensitive data.

Global color policy and per-level appearance are separate.  `bashlog_color_set`
controls whether styling may be emitted; `bashlog_level_style_set` controls the
symbolic color and intensity of a severity token when styling is allowed.  Raw
ANSI is deliberately excluded from the public style configuration surface.

The ANSI reset must immediately follow the severity token.  Do not widen the
bashlog-owned style span to timestamps, tags, punctuation, or message content
without a new architectural decision.

### Ambient Shell State

Bash's `nocasematch` option affects both `[[ string == pattern ]]` and
`[[ string =~ regex ]]`, while bashlog's glob and ERE contract is case-sensitive.
The matcher implementation therefore preserves the caller's prior `nocasematch`
state, temporarily disables it only around the individual Bash-native comparison,
and restores the prior state before returning.  Tests explicitly exercise this
behavior.

The library does not change caller locale.  Glob and ERE semantics remain subject
to Bash/libc locale behavior documented by the specification.  The `fixed`
matcher remains the recommended mode for exact known multibyte secrets.

### ERE Match Location

Bash 4.3 exposes matched ERE text through `BASH_REMATCH` but does not provide a
portable match-offset API.  The implementation must not locate a selected match
by searching for the first literal copy of `BASH_REMATCH[0]`; that would be wrong
for anchored expressions when identical text appears earlier.

`lib/redaction-core.bash` therefore determines candidate start positions against
the original rule input and forces the ERE to begin at each candidate position,
preserving whole-input `^` and `$` semantics.  Anchored ERE regression tests are
part of the active suite.  Changes to this algorithm deserve security-sensitive
review.

## Validation

Use the smallest relevant set first, then the full project contract:

```text
make check
make test
make test-report
make docs
make deps-check
```

`make check` validates every maintained runtime module.  Its ShellCheck exclusions
are narrowly scoped in the Makefile and document intentional language use:

- SC2053 for the dynamic right-hand Bash glob matcher;
- SC2059 for the documented caller-supplied `printf` format string;
- SC2154 where a module consumes globals declared by an earlier module in the
  explicit assembly order.

Do not broaden these exclusions casually.  Narrow inline SC2154 suppressions are
appropriate where presentation code deliberately consumes level-normalization
output declared by the earlier `lib/level.bash` module.

The active Bats suite under `tests/contract/` runs against development, ordinary,
and minified artifacts.  Security-sensitive tests use negative assertions as well
as positive assertions: protected originals must not appear in standard output,
standard error, failure diagnostics, or alternate severity paths.

Presentation tests must verify exact ANSI placement when color is forced,
including that only the severity token is styled and that logfmt contains no
bashlog-owned ANSI.  The Bash 4.3 fixture exercises representative style getters,
overrides, resets, and rendered style behavior across every generated artifact.

Contract child programs are passed to clean Bash processes through standard input
with `bash -s -- ...` rather than embedded inside another single-quoted
`bash -c` program.  This preserves quotes, substitutions-as-data, Unicode, and
pattern syntax exactly as the fixture expresses them.

`tests/contract/compat-bash43.bash` is run against all three generated artifacts
inside Bash 4.3 in CI and release validation.  If a correct and auditable
implementation can no longer satisfy the Accepted contract on Bash 4.3, revisit
ADR-002 explicitly rather than weakening the tests or hiding version-dependent
behavior.

## Scope Discipline

Prefer the smallest coherent change that satisfies the governing decision.  Do
not mix unrelated cleanup into functional work.  Record useful but orthogonal
ideas separately rather than expanding scope without acknowledgment.

When changing architecture, update or add an ADR before or with implementation.
Update `doc/decisions.md` when the operative decision changes.  When changing
observable public behavior, update `doc/bashlog-spec.md` before or with the
implementation, Doxygen contracts, and tests.  Compare completed work back
against the governing ADR constraints so locally correct changes do not create
architectural drift.
