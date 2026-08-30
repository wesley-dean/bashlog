# Architectural Decisions

This document is a concise map of bashlog's Architecture Decision Records.
Each entry summarizes the operative decision in one to three sentences and links
to the full ADR, where the context, reasoning, promises, non-promises, failure
model, alternatives, consequences, and follow-up questions are preserved.

This file is intentionally **not** a substitute for the ADR corpus.  When a
summary and a governing ADR appear to conflict, read the ADR and surface the
conflict rather than silently choosing the shorter wording.

The Accepted ADRs below describe current architectural decisions.  Proposed ADRs
are documented separately and do not supersede Accepted behavior until ratified.
The accepted normative public behavior derived from Accepted decisions is
documented in [`doc/bashlog-spec.md`](bashlog-spec.md).

## Accepted Decisions

### ADR-000: Capability Scope, Epistemic Honesty, and Separation of Concerns

Accuracy, explicit capability limits, evidence-oriented reasoning, separation of
concerns, and resistance to sycophantic or performative agreement are foundational
project constraints.  The project prefers truthful, reviewable boundaries over
claims made primarily to sound helpful or reassuring.

See [ADR-000](adr/ADR-000-capability-scope-and-epistemic-honesty.md).

### ADR-001: Documentation and Decision Hierarchy

ADRs are the canonical record of durable architectural reasoning;
`doc/decisions.md` is the concise decision map; `AGENTS.md` is an operational
navigation aid; Doxygen comments own implementation-level contracts;
`doc/bashlog-spec.md` owns normative public behavior; and tests provide evidence
rather than superseding architectural intent.

See [ADR-001](adr/ADR-001-documentation-and-decision-hierarchy.md).

### ADR-002: Bash Runtime and Portability Baseline

bashlog targets Bash 4.3 or newer and avoids post-4.3 runtime features unless a
later ADR intentionally raises the minimum.  The floor should be revisited if a
newer Bash version materially improves correctness, security, readability, or
auditability rather than merely providing convenience.

See [ADR-002](adr/ADR-002-bash-runtime-and-portability-baseline.md).

### ADR-003: Make as the Canonical Orchestration Interface

GNU Make is the canonical development and CI orchestration surface.  Build,
dependency, documentation, formatting, testing, and cleanup semantics belong in
stable Make targets, with `build` remaining separate from dependency acquisition.

See [ADR-003](adr/ADR-003-make-as-canonical-orchestration-interface.md).

### ADR-004: Modular Source Assembly and Automatically Discovered Plugins

Maintained implementation uses explicitly ordered core source plus
deterministically discovered additive modules, assembled into standalone
consumer artifacts.  ADR-016 supersedes the inherited runtime-registry/noop
portions for bashlog while retaining the useful modular assembly principles.

See [ADR-004](adr/ADR-004-modular-source-and-plugin-discovery.md) and
[ADR-016](adr/ADR-016-modular-source-assembly-for-a-sourceable-library.md).

### ADR-005: Dependency Management and Explicit Network Boundaries

bashdeps manages pinned repository dependencies such as scripts, filters, and
assets, while system tools remain outside bashdeps scope.  `deps` may acquire or
repair dependency state; build, documentation, test, and verification targets
consume prepared state without silently synchronizing it.

See [ADR-005](adr/ADR-005-dependency-management-and-network-boundaries.md).

### ADR-006: Three Release Artifact Flavors, Metadata, and Checksums

Builds produce documented development, comment-stripped ordinary, and minified
standalone Bash artifacts with version/build provenance and adjacent SHA-256
checksum companions.  All artifact flavors are expected to exhibit equivalent
public behavior.

See [ADR-006](adr/ADR-006-release-artifact-flavors-and-metadata.md).

### ADR-007: Doxygen-Based Verbose Source Documentation Standard

Maintained Bash uses the exact `bash-doxygen`-compatible `##` Doxygen model,
including structured `@file`, `@fn`, `@var`, `@param`, `@brief`, `@details`,
return/output documentation, and examples as applicable.  This syntax and
structure are normative; a merely similar comment style is not an acceptable
substitute.

See [ADR-007](adr/ADR-007-doxygen-verbose-source-documentation.md) and
[the source documentation standard](documentation-standard.md).

### ADR-008: Documentation-Driven, Test-Second Development

Consequential behavior should be documented architecturally and at the interface
level before tests encode the intended contract and implementation follows.
Exploratory code may precede documentation for feasibility work but must not
silently become accepted architecture.

See [ADR-008](adr/ADR-008-documentation-driven-test-second-development.md).

### ADR-009: Observable Behavior Testing Across Shipped Artifacts

Bats is the default behavior-testing framework, and the same public behavior
suite runs against development, ordinary, and minified artifacts.  Tests should
be focused enough that failures identify a primary contract, while release
validation exercises the exact artifacts intended for publication.

See [ADR-009](adr/ADR-009-observable-behavior-testing.md).

### ADR-010: Generated Reference Documentation Is Ephemeral

Doxygen reference output is generated under `doc/reference/`, consumes prepared
`bash-doxygen` state, and is not committed.  Maintained source comments and ADRs
remain authoritative while generated documentation may be published by CI.

See [ADR-010](adr/ADR-010-generated-reference-documentation.md).

### ADR-011: Conventional-Commit Semantic Releases and Late Tagging

Release versions are derived from Conventional Commits, and the release/tag is
created only after dependency preparation, checks, builds, tests, checksum
verification, and artifact attestation succeed.  Publication is a consequence of
successful validation rather than a prerequisite for it.

See [ADR-011](adr/ADR-011-conventional-semver-and-late-tagging.md).

### ADR-012: Standardize SHA-256 Checksum Companion Filenames

Current builds and releases use `.sha256` checksum companion filenames and do not
publish duplicate `.256` files.  Historical `.256` release assets remain valid,
and cross-generation readers may fall back to them only after confirmed absence
of the preferred `.sha256` resource, not after transport or verification errors.

See [ADR-012](adr/ADR-012-standardize-sha256-checksum-companion-filenames.md).

### ADR-013: Sourceable Library Scope and Responsibility Boundary

bashlog is a narrowly scoped, sourceable logging/redaction library: loading it
does not install traps, change shell options, create generic aliases or
functions, access the network, or assume application control-flow policy.  The
caller owns application data acquisition and application-specific transformation;
bashlog owns logging-related processing within its documented boundary.

See [ADR-013](adr/ADR-013-sourceable-library-scope-and-responsibility-boundary.md).

### ADR-014: Pure Bash Runtime and External Command Boundary

Runtime bashlog behavior uses Bash language facilities and builtins only, with no
external commands in sourcing, formatting, redaction, rendering, or emission.
Caller-selected external commands remain caller-owned, and development or release
tooling is explicitly outside the consumer runtime boundary.

See [ADR-014](adr/ADR-014-pure-bash-runtime-and-external-command-boundary.md).

### ADR-015: Namespaced Public API and Caller-Owned Convenience Wrappers

The public API uses stable `bashlog_*` names, with visibly internal `__bashlog_*`
implementation names and no claim that Bash provides true privacy.  Generic names
such as `info`, `warn`, `error`, and `die` remain caller-owned and may be created
through explicit wrapper functions rather than aliases, `eval`, or exported-
function machinery.

See [ADR-015](adr/ADR-015-namespaced-public-api-and-caller-owned-convenience-wrappers.md).

### ADR-016: Modular Source Assembly for a Sourceable Library

bashlog retains explicit core ordering and deterministic additive module discovery
while dropping the template's runtime plugin registry and noop plugin.  Modularity
is a maintenance/build concern; consumers receive a standalone sourceable
artifact and do not perform runtime plugin discovery.

See [ADR-016](adr/ADR-016-modular-source-assembly-for-a-sourceable-library.md).

### ADR-017: Logging Pipeline, Levels, Formatting, and Emission

All bashlog-provided logging helpers converge through a common pipeline.  ADR-026
supersedes the original complete-render-before-redaction ordering: logger-managed
redaction now protects caller semantic fields before rendering, while the final
sink-bound verification remains immediately before emission.

See [ADR-017](adr/ADR-017-logging-pipeline-levels-formatting-and-emission.md) and
[ADR-026](adr/ADR-026-adaptive-human-logfmt-rendering-and-stderr-transport.md).

### ADR-018: Redaction as an Opt-In Security Boundary

Redaction is explicit defense in depth: bashlog does not guess which values are
sensitive, but once a rule is accepted and its context is explicitly invoked,
honoring it becomes a security obligation for that bashlog operation.  Redaction
failure suppresses the protected record, replacement text is always literal, and
the project makes no secure-memory or hostile-same-process-code claim.

See [ADR-018](adr/ADR-018-redaction-as-an-opt-in-security-boundary.md).

### ADR-019: Readability, Auditability, and Rejection of Obscurity

Security-sensitive implementation treats readability and auditability as
correctness properties.  bashlog does not rely on obscure names, reversible
encoding, `eval`, generated code, or fake encapsulation as security controls; the
critical path should be directly understandable from maintained Bash source and
its exact Doxygen documentation.

See [ADR-019](adr/ADR-019-readability-auditability-and-rejection-of-obscurity.md).

### ADR-020: Redaction Context Lifecycle and State Model

Redaction contexts follow a monotonic `unseen -> active -> destroyed` lifecycle:
the first successful rule addition creates an active context, active contexts are
append-only, and whole-context destruction is one-way for the process without
claiming secure erasure.  Explicitly requesting an unknown, invalid, or destroyed
context fails closed rather than silently behaving like an empty rule set.

See [ADR-020](adr/ADR-020-redaction-context-lifecycle-and-state-model.md).

### ADR-021: Redaction Rule Registration, Ordering, and Replacement Semantics

Rules require an explicit `fixed`, `glob`, or `ere` matcher, validate atomically
before append, preserve exact registration order, reject duplicate matcher/pattern
pairs, and perform one bounded global pass per rule.  Replacement text is always
literal, empty replacement is valid, and a rule whose replacement still matches
itself is rejected rather than accepted as predictably unsatisfiable.

See [ADR-021](adr/ADR-021-redaction-rule-registration-ordering-and-replacement.md).

### ADR-022: Fixed-String Redaction and Multibyte Guarantees

`fixed` is the strongest matcher for known secrets: every pattern character is
literal, every non-overlapping exact occurrence is replaced, and an exact
representable multibyte sequence is protected without glob, ERE, case-fold, or
Unicode-normalization semantics.  Embedded NUL data remains outside the Bash
string model and is explicitly not claimed as supported.

See [ADR-022](adr/ADR-022-fixed-string-redaction-and-multibyte-guarantees.md).

### ADR-023: Glob and ERE Redaction Semantics

`glob` uses a deliberately limited basic Bash pattern language with no extglob
dependency, while `ere` uses Bash `[[ =~ ]]` extended regular expressions; both
operate case-sensitively in the caller's current locale.  Invalid EREs and any
glob/ERE capable of matching empty text are rejected so global replacement
remains bounded and auditable.

See [ADR-023](adr/ADR-023-glob-and-ere-redaction-semantics.md).

### ADR-024: Final Redaction Verification and Fail-Closed Output Boundary

After each semantic field's ordered transformation and verification, a logging
call that selected a context finally rechecks the complete rendered candidate
against that same context before emission.  Any remaining match or matcher error
suppresses the candidate; bashlog does not repeatedly rewrite until a fixed point,
and safe diagnostics remain bounded and fail closed.

See [ADR-024](adr/ADR-024-final-redaction-verification-and-fail-closed-output.md)
and [ADR-026](adr/ADR-026-adaptive-human-logfmt-rendering-and-stderr-transport.md).

### ADR-025: Optional Presentation Metadata, Tags, and Color

bashlog provides Bash-native optional timestamps, repeatable per-call tags, and
severity-aware styling for the human renderer.  Timestamping remains off by
default, tags remain explicit, and color defaults to `auto`; logfmt output never
contains bashlog-owned ANSI styling.

See [ADR-025](adr/ADR-025-optional-presentation-metadata-tags-and-color.md).

### ADR-026: Adaptive Human/Logfmt Rendering and Environment-Agnostic Stderr Transport

Standard error remains the universal sink, while `format=auto` selects human
output when fd 2 is a TTY and deterministic logfmt when it is not.  Redaction
remains explicit and developer-owned: callers create/populate the applicable
context, then either invoke `bashlog_redact` directly or pass `--context CONTEXT`
to a logging call; primary logger-managed redaction occurs before renderer
serialization, and bashlog does not infer deployment infrastructure.

See [ADR-026](adr/ADR-026-adaptive-human-logfmt-rendering-and-stderr-transport.md).

### ADR-027: Configurable Severity Token Styles

Global `never|auto|always` color policy determines whether human severity styling
may be emitted, while per-level symbolic style determines the canonical severity
token's foreground color and `normal|bold|dim` intensity.  Styling is limited to
the severity signifier, resets immediately after it, is independently resettable,
accepts no raw ANSI/SGR input, and never affects logfmt output.

See [ADR-027](adr/ADR-027-configurable-severity-token-styles.md).
