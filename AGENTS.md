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
   `doc/adr/README.md` as the generated index.
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
- `doc/adr/README.intro.md` and `doc/adr/README.outro.md`: maintained framing for
  the generated ADR directory landing page.
- `doc/adr/README.md`: generated, committed ADR navigation; regenerate with
  `make adr-index` rather than editing its ADR list directly.
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
- `make adr-index` is offline and regenerates the committed `doc/adr/README.md`
  using prepared `vendor/adrctl.bash` plus maintained intro/outro fragments.
- `make docs` is offline, regenerates the ADR index, and consumes the prepared
  `bash-doxygen` filter to generate ephemeral Doxygen reference output.

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

All three distribution artifacts expose the same public API and runtime contract.
The development artifact retains maintained comments, the ordinary artifact strips
full-line comments, and the minified artifact applies the pinned Bash-Minifier.
Generated artifacts are products and must be tested directly.

## Public API Boundary

The supported public API consists of documented `bashlog_*` functions and
project metadata variables explicitly identified by the specification.  Names
beginning `__bashlog_` are internal implementation details and are not compatibility
commitments.

Source-time behavior is intentionally non-invasive.  Do not add shell-option
changes, traps, network access, filesystem mutation, generic aliases/functions,
automatic secret discovery, dynamic plugin loading, or runtime external commands
without a new Accepted architectural decision.

## Security-Relevant Invariants

- redaction policy is developer-defined rather than inferred;
- once an accepted context is explicitly selected, redaction is fail-closed;
- replacement text is always literal;
- primary logger-managed redaction protects semantic caller fields before
  presentation;
- the final rendered candidate is verified again before emission;
- the human renderer and logfmt renderer have different control-byte handling,
  which is documented as residual risk rather than hidden;
- caller-side xtrace can expose arguments before bashlog receives them;
- same-process hostile code and secure memory erasure are not claimed boundaries;
- every added dependency is new trusted code and must be reviewed as such.

Do not broaden a security promise merely because current implementation behavior
appears stronger than the documented contract.  Update the governing ADR,
specification, threat model, tests, and implementation deliberately when changing
a security boundary.

## Documentation Rules

Consequential architectural changes require an ADR.  Public behavior changes
require a synchronized specification update.  Maintained Bash comments must use
the exact syntax and structure documented in `doc/documentation-standard.md`.

`doc/adr/README.md` is a generated, committed navigation surface.  Change its
stable prose through `README.intro.md` or `README.outro.md`, change ADR titles in
the governing ADR files, then regenerate with `make adr-index`.  Do not maintain a
second hand-written ADR title list.

Prefer durable invariants over mutable snapshots.  Do not document exact test
counts, generated line counts, or other values that become false when ordinary
maintenance changes an implementation detail without changing the contract.

## Release Posture

Releases are created only after the exact intended source revision and artifacts
have passed the required validation.  Current checksum companions use `.sha256`;
historical `.256` assets may be read only through documented compatibility
fallback behavior.

Read `doc/release-verification.md` before changing tag timing, checksum handling,
artifact publication, attestation, or dependency provenance behavior.
