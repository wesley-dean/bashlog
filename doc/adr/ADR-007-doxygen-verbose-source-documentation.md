# ADR-007: Doxygen-Based Verbose Source Documentation Standard

Date: 2026-08-19

## Status

Accepted

## Intent and Documentation Posture

This ADR establishes the exact source-documentation model for maintained Bash
code in bashlog.

The model is not merely inspired by Doxygen-compatible comments used elsewhere.
It is the same `##`-based structure used by bashdeps, Bootstrap, mktext, adrctl,
template-bash, and related projects and consumed by the `bash-doxygen` tooling.
Compatibility with that syntax and toolchain is an explicit project requirement.

The project deliberately prefers a "more is more" documentation posture.
Additional documentation is desirable when it preserves intent, contracts,
assumptions, invariants, edge cases, failure semantics, security boundaries,
examples, interactions, or reasoning that would otherwise have to be inferred
from executable Bash.

Source brevity is not a goal when it competes with understanding.

## Context

Bash is highly expressive but provides little native structure for communicating
contracts, types, failure semantics, invariants, or architectural intent.  Code
that is straightforward to execute can still be expensive to maintain when the
reasoning behind it must be reconstructed from control flow.

The project family uses `bash-doxygen`, a Bash-aware Doxygen filter that consumes
contiguous `##` documentation blocks immediately associated with documented Bash
declarations.  The filter deliberately documents only declarations that carry a
Doxygen block, making documentation placement and syntax part of the maintained
source contract.

The filter recognizes structural commands including:

- `@file`;
- `@fn`;
- `@var`;
- and `@param` names;

while preserving normal Doxygen commands such as:

- `@brief`;
- `@details`;
- `@param`;
- `@returns`;
- `@retval`;
- `@note`;
- `@warning`;
- `@see`;
- `@par`;
- `@code` / `@endcode`;
- and supported custom aliases.

The project already carries `doc/documentation-standard.md` describing the
expected file and function structure.  This ADR makes clear that a future
maintainer must not replace the established syntax with something merely similar
because another comment style looks cleaner or another documentation generator
can be made to accept it.

The need is stronger in bashlog than in an ordinary utility.  Redaction and final
emission are security-sensitive paths.  A future reviewer should not have to
infer quoting assumptions, replacement semantics, failure behavior, or threat
boundaries from shell syntax alone.

Verbose source documentation does not impose a distribution-size penalty here.
The ordinary release artifact removes full-line comments, and the minified
artifact is smaller still.  The development artifact intentionally preserves the
commentary needed to maintain and review the generated single-file form.

## Decision Drivers

- Preserve local reasoning near the implementation that depends on it.
- Make Bash interfaces and failure behavior explicit.
- Use the proven `bash-doxygen` tooling without a parallel documentation syntax.
- Generate browsable reference documentation without maintaining duplicate API
  prose manually.
- Support human and AI-assisted maintenance with enough context to avoid
  inference from code alone.
- Make security-sensitive assumptions visible beside the code they constrain.
- Prefer maintainability over source-file brevity.
- Keep documentation structure consistent across the related Bash project family.

## Decision

All maintained Bash source SHALL use the project's exact Doxygen-based
documentation standard described in `doc/documentation-standard.md` and supported
by `bash-doxygen`.

The standard is normative.  It is not a suggestion, inspiration, or invitation
to use an approximately equivalent comment style.

### Documentation Comment Syntax

Doxygen documentation lines SHALL begin with two hash characters:

```bash
## @file lib/example.bash
## @brief Provides an example capability.
## @details
## This module exists to preserve a specific contract.  The details explain why
## the capability belongs here, how callers should use it, and what assumptions
## future changes must preserve.
```

Ordinary single-hash comments MAY be used for narrow implementation annotations
that are not intended to become part of generated reference documentation.

A contributor MUST NOT replace the established `##` Doxygen blocks with another
comment convention merely because Doxygen itself can be configured to consume
it.  Changing the source documentation syntax or its relationship to
`bash-doxygen` is an architectural change requiring a superseding ADR.

### File Documentation

Every maintained sourced or assembled Bash fragment SHOULD begin with:

```bash
# shellcheck shell=bash
## @file path/to/file.bash
## @brief One-sentence purpose.
## @details
## Substantive documentation follows.
```

`@details` SHALL explain module responsibility, relationship to neighboring
modules, important state ownership, assumptions, relevant failure behavior, and
constraints needed for safe maintenance.

A useful file block answers **why the module exists**, not merely which functions
it happens to contain.

### Function Documentation

Significant functions SHALL use the established function-block structure as
applicable:

```bash
## @fn example_lookup()
## @brief Looks up a named example.
## @details
## Explain the contract, assumptions, side effects, failure behavior, and why the
## function exists.  Explain non-obvious interactions with neighboring modules.
##
## @param name Logical name to look up.
## @par Standard Output
## The matching value when one exists.
## @retval 0 A matching value was found.
## @retval 64 The caller supplied invalid input.
## @retval 69 No matching value exists.
## @par Examples
## @code
## value="$(example_lookup demo)"
## @endcode
example_lookup() {
  # implementation
}
```

Parameters SHALL be documented in call order.  Standard output and standard
error SHALL be documented when callers depend on them.  Return values SHALL be
documented semantically when distinct failures matter.

Examples are strongly preferred for public, parsing, transformation, plugin,
redaction, formatting, and otherwise non-trivial interfaces.

### Variables and Constants

Documented variables and constants SHOULD use `@var` when appropriate so
`bash-doxygen` can validate that the documented name matches the following
declaration:

```bash
## @var BASHLOG_DEFAULT_LEVEL
## @brief Default logging threshold used when the caller has not configured one.
readonly BASHLOG_DEFAULT_LEVEL='info'
```

Exported variables, configuration state, registries, security-sensitive arrays,
and constants whose meaning is not self-evident SHALL document ownership,
allowed values, mutability, lifecycle, and units as applicable.

The project does not require documentation for every local loop variable.
Documentation volume should preserve reasoning rather than create noise that
hides it.

### Private/Internal Helpers

Internal helpers may use shorter Doxygen blocks when their contract is genuinely
narrow and obvious from the surrounding module.

They SHALL receive fuller documentation when they encode:

- tricky Bash expansion behavior;
- quoting assumptions;
- pattern or regular-expression behavior;
- error translation;
- security boundaries;
- redaction ordering;
- replacement semantics;
- locale or multibyte assumptions;
- portability workarounds;
- or dependency ordering.

An `__bashlog_*` name is not a reason to omit documentation when the function is
important to the security path.

### bash-doxygen Compatibility

Maintained documentation SHALL remain compatible with the project's pinned
`bash-doxygen` filter.

The filter's structural relationship between a Doxygen block and the declaration
that follows it is part of the source contract.  Documentation MUST remain placed
so the filter can associate the block with the intended function or variable.

Where practical, documentation validation SHOULD use `bash-doxygen` diagnostics
strictly enough to detect mismatched `@fn`/`@var` names, orphaned blocks, or other
documentation drift.

### Relationship to ADRs and Specifications

Doxygen source documentation owns implementation-level intent and current
function/module contracts.

ADRs own durable architectural reasoning, rejected alternatives, and the reasons
behind security or compatibility boundaries.

The normative project specification, once created, owns current public behavior.

Source comments MAY reference ADRs when a local implementation exists to satisfy
a particular architectural constraint.  They SHOULD NOT copy an entire ADR into
the source or invent historical rationale that no record supports.

### Maintained Versus Consumer Representations

The `.dev.bash` artifact SHALL retain the maintained Doxygen commentary.

The ordinary `.bash` artifact and `.min.bash` artifact SHALL allow maintainers to
retain verbose source documentation without imposing that size on every consumer.

Maintainers MUST NOT reduce documentation merely to shrink generated consumer
artifacts.

## Promises

1. **The syntax is stable and explicit.**  Maintained Bash documentation uses
   contiguous `##` Doxygen blocks with the established structural commands and
   declaration relationship.

2. **bash-doxygen compatibility is intentional.**  The documentation model is
   designed for the same tooling used across the related Bash projects.

3. **Security-sensitive behavior receives implementation documentation.**  The
   fact that a helper is internal does not exempt non-obvious redaction or Bash
   semantics from explanation.

4. **Maintainer documentation is preserved in the development artifact.**
   Reviewers can inspect the assembled consumer-order source with its reasoning
   intact.

5. **Source size does not drive documentation removal.**  Consumer stripping and
   minification exist specifically so maintained source can remain verbose.

## Non-Promises

1. Doxygen comments do not replace ADRs for architectural history or rejected
   alternatives.

2. Generated HTML does not become the maintained source of truth.

3. The documentation standard does not require comments that merely paraphrase
   self-evident Bash syntax.

4. A successful documentation build does not prove that every explanation is
   semantically correct.  Documentation still requires review against code,
   tests, specifications, and ADRs.

5. `bash-doxygen` compatibility does not require bashlog to expose undocumented
   internal helpers in generated reference output.

## Adversary and Failure Model

This decision is intended to prevent documentation failures such as:

- a future maintainer replacing `##` blocks with a superficially similar style
  that breaks `bash-doxygen` association;
- `@fn` or `@var` documentation drifting away from the declaration it describes;
- security-sensitive code being left undocumented because the helper is
  considered "private";
- comments describing what a command does while omitting why a non-obvious Bash
  construct is necessary;
- maintainers removing useful source documentation to reduce artifact size;
- generated reference output being mistaken for authoritative maintained source;
- and AI-assisted edits rewriting documentation to match accidental code drift
  without checking the governing ADR.

The model assumes `bash-doxygen` itself is a development dependency managed and
verified according to the repository dependency ADRs.  A compromised development
or CI environment is outside the documentation syntax decision itself.

## Operational Constraints

- Maintained Bash files MUST use Doxygen-compatible `##` documentation blocks.
- The documentation syntax MUST remain compatible with `bash-doxygen`.
- File blocks MUST use the established `@file`, `@brief`, and substantive
  `@details` structure.
- Significant functions MUST use `@fn`, `@brief`, `@details`, parameters,
  outputs, return semantics, and examples as applicable.
- Documented significant variables SHOULD use `@var` where doing so allows
  `bash-doxygen` name validation.
- Documentation blocks MUST remain adjacent to the declarations they document in
  the form expected by `bash-doxygen`.
- Non-obvious security-sensitive helpers MUST receive substantive Doxygen
  documentation even when they are internal.
- Documentation MUST preserve reasoning and assumptions rather than merely
  paraphrase code.
- Source documentation MUST NOT be reduced solely to shrink release artifacts.
- `.dev.bash` MUST retain maintained documentation comments.
- A change to the established Doxygen comment syntax or bash-doxygen integration
  MUST require an explicit architectural decision rather than incidental restyle.

## Considered Alternatives

### Sparse Conventional Comments

Sparse `#` comments would keep source visually compact.

They were rejected because they do not provide a consistent interface vocabulary,
are not the established project-family standard, and do not provide the same
`bash-doxygen` reference generation and validation path.

### A Similar but Different Doxygen Syntax

Doxygen can consume many comment formats, and a derived project could choose
`##<`, `#**`, or another structure with enough configuration.

It was rejected because consistency with the existing Bash project family and
`bash-doxygen` tooling is an explicit requirement.  There is no benefit in
creating a nearly identical local dialect.

### External-Only API Documentation

API documentation could be written entirely under `doc/` and kept out of source.

It was rejected because implementation rationale and function contracts drift
more easily when they are separated from the code they constrain.

### Minimal Comments Plus AI Inference

A future maintainer could ask an AI tool to explain undocumented code.

It was rejected because plausible inference is not evidence of original intent.
The project wants reasoning preserved, not reconstructed probabilistically.

### Document Only Public Functions

Generated reference documentation would be smaller and more consumer-oriented.

It was rejected as a blanket rule because important internal redaction helpers
may encode the project's most security-sensitive assumptions.  Documentation
need is determined by maintenance significance, not only public visibility.

## Consequences

Maintained Bash files are intentionally longer.  Reviews must evaluate comment
accuracy along with executable behavior.

The project remains compatible with the documentation workflow already proven in
the related Bash repositories.  Contributors familiar with those projects do not
need to learn a bashlog-specific comment dialect.

Security review benefits because implementation-level assumptions are preserved
at the point where they matter, while ADRs remain available for the deeper
reasoning and rejected alternatives.

## Source Lineage

The standard consolidates documentation practices used across Bootstrap,
adrctl, bashdeps, mktext, template-bash, and bash-doxygen and is informed by:

- https://wesleydean.com/blog/bash_help_documentation_project/
- https://wesleydean.com/blog/documentation_and_ai/

The `bash-doxygen` project is the normative tooling reference for the source
comment structure used by bashlog.

## Open Questions and Follow-Ups

- The Doxygen build may be tightened to run the bash-doxygen filter in strict mode
  if the current Doxyfile integration can do so cleanly without creating a second
  wrapper implementation.
- The project should add documentation-focused tests or CI checks if future drift
  demonstrates that Doxygen generation alone does not catch important structural
  errors.

## Related Decisions

- ADR-001: Documentation and Decision Hierarchy
- ADR-005: Dependency Management and Explicit Network Boundaries
- ADR-008: Documentation-Driven, Test-Second Development
- ADR-010: Generated Reference Documentation Is Ephemeral
- ADR-019: Readability, Auditability, and Rejection of Obscurity
