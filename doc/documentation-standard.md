# Bash Documentation Standard

This document defines the normative source-documentation standard for maintained
Bash files in bashlog.  The standard deliberately prefers verbose, explanatory
documentation.  Source brevity is not a goal when brevity would force a future
maintainer to infer intent, contracts, assumptions, failure semantics, security
boundaries, or architectural relationships from executable code alone.

This is the same documentation model used across related projects such as
bashdeps, Bootstrap, mktext, adrctl, and template-bash.  It is intentionally
compatible with the `bash-doxygen` tooling.  The syntax and structure described
here are requirements, not examples of a general style that may be replaced with
something merely similar.

The distribution pipeline separates maintenance representation from consumer
representation.  The `.dev.bash` artifact retains documentation.  Full-line
comments are removed from the ordinary `.bash` artifact, and Bash-Minifier
produces the `.min.bash` artifact.  Maintainers therefore should not reduce
source documentation merely to optimize release size.

See ADR-007 for the architectural decision governing this standard.

## Comment Syntax

Doxygen documentation lines begin with exactly two hash characters:

```bash
## @file lib/example.bash
## @brief Provides an example capability.
## @details
## This module exists to preserve a specific contract.  The details explain why
## the capability belongs here, how callers should use it, and what assumptions
## future changes must preserve.
```

Use ordinary single-hash comments for narrow implementation annotations that are
not intended to become part of generated reference documentation.  Prefer
Doxygen comments whenever the material helps explain an interface, invariant,
module responsibility, non-obvious decision, maintenance constraint, portability
assumption, or security boundary.

The project does not use another Doxygen comment dialect in maintained Bash
source.  Do not replace these blocks with `#**`, `##<`, or another convention
without an architectural decision that explicitly changes ADR-007 and the
`bash-doxygen` integration.

## Relationship to bash-doxygen

`bash-doxygen` converts documented Bash declarations into a Doxygen-friendly
intermediate representation.  It intentionally emits declarations only when they
are decorated with a Doxygen block.

Documentation blocks must therefore remain contiguous and associated with the
function or variable declaration they document.

The filter structurally understands `@file`, `@fn`, `@var`, and `@param` names and
preserves ordinary Doxygen commands such as `@brief`, `@details`, `@returns`,
`@retval`, `@note`, `@warning`, `@see`, `@par`, `@code`, and `@endcode`.

When `@fn` or `@var` is used, the documented name must agree with the declaration
that follows.  Maintainers should prefer the explicit structural commands because
they allow tooling to catch documentation drift.

## File Blocks

Every maintained Bash source fragment should begin with:

- `# shellcheck shell=bash` when the file is a sourced/assembled fragment without
  its own shebang;
- `## @file <path>`;
- `## @brief <one-sentence purpose>`; and
- `## @details` followed by substantive prose.

For example:

```bash
# shellcheck shell=bash
## @file lib/redaction.bash
## @brief Provides the core redaction pipeline.
## @details
## Explain the module's responsibility, state ownership, security boundary,
## interactions with formatting/emission, and assumptions future changes must
## preserve.
```

The details should explain the module's responsibility, its relationship to
neighboring modules, important state it owns, and assumptions that affect safe
modification.  A useful file block answers "why does this module exist?" as well
as "what functions are in it?"

Security-sensitive modules should explicitly identify the boundary they enforce
and link to governing ADRs when that context materially improves review.

## Function Blocks

Significant functions should use the following vocabulary as applicable:

```bash
## @fn example_lookup()
## @brief Looks up a named example.
## @details
## Explain the contract, assumptions, side effects, and why the function exists.
## Describe non-obvious behavior and interactions with other modules.
##
## @param name Logical name to look up.
## @par Standard Output
## The matching value when one exists.
## @par Standard Error
## A diagnostic when the request is invalid or the lookup cannot be completed.
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

Document parameters in call order.  Document standard output and standard error
when callers depend on them.  Document return values semantically rather than
merely saying "success" or "failure" when distinct failures matter.

Examples are strongly preferred for public, plugin, parsing, transformation,
redaction, formatting, emission, or otherwise non-trivial interfaces.  Examples
should demonstrate intended use, not manufacture a second test suite inside
comments.

For security-sensitive functions, `@details` should explain the important
preconditions, failure behavior, ordering assumptions, and what the function must
never emit or expose.

## Variables and Constants

Document exported variables, configuration knobs, registry structures,
security-sensitive arrays, and constants whose meaning is not self-evident.
Explain units, allowed values, mutability, ownership, lifecycle, and whether the
value participates in public API compatibility when those details matter.

Use `@var` for significant documented variables where appropriate:

```bash
## @var BASHLOG_DEFAULT_LEVEL
## @brief Default logging threshold used when no caller override exists.
readonly BASHLOG_DEFAULT_LEVEL='info'
```

Using `@var` allows `bash-doxygen` to verify that the documentation name matches
the following declaration.

Do not document every local loop variable.  Documentation volume should preserve
reasoning, not create noise that obscures it.

## Internal Helpers

Internal helpers may use shorter Doxygen blocks when their contract is narrow and
obvious from the surrounding module.  They still require fuller documentation
when they encode a tricky shell behavior, quoting assumption, error translation,
security boundary, portability workaround, ordering dependency, locale behavior,
pattern-matching rule, redaction invariant, or failure path.

A function beginning with `__bashlog_` is internal by project convention.  That
prefix is not a privacy mechanism and is not a reason to omit documentation from
a security-critical helper.

## Security-Sensitive Documentation

For redaction, final rendering, and emission code, comments should make it
possible for a reviewer to answer questions such as:

- what sensitive state the function receives or accesses;
- whether the value is plaintext in the current Bash process;
- whether data can reach a sink from this function;
- whether failure suppresses or emits the original message;
- what matcher semantics apply;
- whether replacement text is interpreted;
- whether locale or multibyte behavior matters;
- what assumptions depend on the Bash compatibility floor;
- and which ADR establishes the relevant security promise.

Do not use comments to imply stronger runtime protection than Bash provides.
Terms such as "private," "secure memory," or "isolated" must not be used for
ordinary same-process variables unless a real mechanism supports the claim.

## Document Intent, Not Syntax

Avoid comments such as "increment the counter" immediately above
`((counter++))`.  Prefer comments that explain why the counter exists, why an
operation occurs at that point, or why a seemingly unusual implementation is
necessary.

If code and documentation disagree, treat the disagreement as a defect to
investigate.  Do not automatically rewrite the comment to match current code;
the code may be the part that drifted from the intended contract.

## Relationship to ADRs

Doxygen documentation owns implementation-level intent.  ADRs own durable
architectural reasoning, promises, non-promises, adversary/failure models,
rejected alternatives, and accepted tradeoffs.  Source comments may link to an
ADR when a local implementation exists specifically to satisfy an architectural
constraint.

Do not copy an entire ADR into source comments.  Do not invent historical
rationale when no source supports it.  State uncertainty or add an ADR when a
new consequential decision is required.

`doc/decisions.md` provides only concise ADR summaries and does not replace either
the full ADR or local Doxygen contract.

Once created, `doc/bashlog-spec.md` will own current public behavior.  Doxygen
comments should agree with that specification for public functions while adding
implementation-level context that would be inappropriate in a consumer-facing
specification.

## Generated Reference Documentation

`make docs` generates reference documentation from maintained source using the
prepared `bash-doxygen` dependency.  Generated output is derivative and is not a
maintained source of truth.

The `.dev.bash` artifact intentionally retains Doxygen comments so reviewers can
inspect the fully assembled source in consumer order.  The stripped and minified
artifacts intentionally allow that source documentation to remain verbose without
forcing all consumers to receive the same comment volume.

## Review Standard

Review documentation with the same seriousness as executable code.  Ask whether
a maintainer unfamiliar with the current implementation could understand:

- the responsibility of each module;
- the contract of each significant function;
- important inputs, outputs, and return semantics;
- invariants and ordering requirements;
- meaningful edge cases and failure modes;
- security-sensitive state and output boundaries;
- why non-obvious implementation choices exist;
- which architectural decisions constrain future changes;
- and what the implementation explicitly does not guarantee.

There is no target comment-to-code ratio.  The desired amount is "enough to
preserve the reasoning."  In this project that may often be more prose than
teams accustomed to sparse Bash comments expect, and that is intentional.

## Structural Checklist

Before considering a maintained Bash file adequately documented, verify as
applicable:

- the file has `# shellcheck shell=bash` when it is an assembled fragment;
- the file has `## @file`, `## @brief`, and substantive `## @details`;
- significant functions have `@fn`, `@brief`, and `@details`;
- parameters are documented in call order;
- stdout/stderr contracts are documented when observable;
- meaningful return statuses are documented with `@retval` or equivalent
  Doxygen vocabulary;
- significant variables use `@var` where useful;
- public or non-trivial functions contain an example when an example improves
  understanding;
- documentation blocks remain adjacent to the declarations consumed by
  `bash-doxygen`;
- and security-sensitive code documents the assumptions a future reviewer would
  otherwise have to infer.
