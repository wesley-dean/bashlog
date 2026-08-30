# ADR-021: Redaction Rule Registration, Ordering, and Replacement Semantics

Date: 2026-08-30

## Status

Proposed

## Intent and Documentation Posture

This Architecture Decision Record defines how redaction rules enter an active
context, how their order is preserved, how duplicates are handled, and how
replacement text behaves.

The details are security relevant.  A rule-registration API that silently
changes an existing rule, accepts ambiguous duplicates, interprets replacement
text, or partially updates a context after validation failure would make it much
harder for a caller to know what protection an active context actually provides.

The project therefore treats rule registration as a small transactional boundary:
a proposed rule is validated first, then appended as one new immutable rule, or
it is rejected without changing the active context.

## Context

ADR-020 establishes append-only redaction contexts.  That decision requires a
precise definition of what is being appended.

A redaction rule has four conceptual fields:

```text
context
matcher type
pattern
replacement
```

The context identifies the policy object.  The matcher type determines how the
pattern is interpreted.  The pattern identifies content to protect.  The
replacement is the literal text that substitutes for matched content.

The project has already identified three useful matcher families:

- `fixed` for exact literal values such as passwords, tokens, API keys, session
  identifiers, or other known sensitive strings;
- `glob` for Bash-style structural wildcard patterns;
- `ere` for Bash extended regular expressions suitable for structured values.

The matcher type must be explicit because the same text has radically different
meaning under literal, glob, and regular-expression semantics.  A pattern such
as `a.b*` cannot safely be guessed.

Ordering also matters.  Redaction rules are transformations.  The output of one
rule becomes the input to the next rule, and replacement text inserted by an
earlier rule may be visible to a later rule.  If ordering were based on
associative-array iteration, hash order, matcher type, or an implementation
optimization, externally visible behavior could drift without an API change.

Replacement handling is equally important.  Bash parameter substitution and many
regular-expression tools provide special replacement syntax such as `&` or
backreferences.  ADR-018 already rejects those semantics for bashlog.  This ADR
makes the registration and application consequences explicit.

## Decision Drivers

- Make matcher interpretation explicit rather than inferred.
- Preserve deterministic behavior across runs and refactors.
- Keep active contexts append-only and prevent accidental mutation by
  re-registration.
- Reject invalid rules before they alter context state.
- Preserve the literal-replacement security invariant from ADR-018.
- Allow intentional deletion of matched text by using an empty replacement.
- Avoid rules that are structurally incapable of eliminating their own match.
- Keep implementation behavior understandable under Bash 4.3.

## Decision

Every accepted redaction rule SHALL record an explicit matcher type, a non-empty
pattern, and a literal replacement.

The supported matcher types for the initial architecture SHALL be exactly:

```text
fixed
glob
ere
```

A caller MUST name the matcher type explicitly.  bashlog SHALL NOT select a
default matcher type based on pattern contents or caller context.

### Registration Is Validate-Then-Append

Rule registration SHALL be atomic with respect to the active context.

bashlog SHALL validate the proposed rule before appending any portion of it to
context state.  If validation fails, the context MUST remain exactly as it was
before the attempted registration.

For a previously unseen context, a failed first rule registration MUST leave the
context unseen, as required by ADR-020.

For an active context, a failed later registration MUST leave all existing rule
contents and order unchanged.

### Non-Empty Patterns

An empty pattern SHALL be invalid for every matcher type.

An empty pattern is not a meaningful secret identifier and can produce
pathological global-match behavior.  Rejecting it at registration is clearer than
attempting to assign matcher-specific empty-pattern semantics.

Matcher-specific ADRs MAY impose additional restrictions, including rejection of
patterns that can match the empty string even when their textual representation
is non-empty.

### Empty Replacements

An empty replacement SHALL be valid.

A caller may intentionally want matched sensitive content removed rather than
replaced by a visible marker.  Treating the replacement as an opaque string means
that the empty string is simply one valid literal replacement value.

### Deterministic Registration Order

Rules SHALL be applied in the exact order in which successful registrations were
accepted into the context.

Registration order is part of the observable redaction contract.

The implementation SHALL preserve that order explicitly.  It MUST NOT rely on
associative-array iteration order, matcher grouping, hash order, lexical sorting,
or another incidental property that can reorder rules.

Each rule receives the current candidate text produced by the preceding rule.
A later rule MAY therefore match text that was present originally or text that
was inserted by an earlier replacement.

### One Global Pass Per Rule

During transformation, each rule SHALL perform one global replacement pass over
its current input according to that matcher's documented semantics.

Matches within that pass SHALL be processed as non-overlapping matches.  Text
inserted as the replacement for the current rule SHALL NOT be recursively
reprocessed by that same rule during the same pass.

After the rule completes, its result becomes the input to the next registered
rule.

bashlog SHALL NOT repeatedly restart the complete rule set until a fixed point is
reached.  Iterative-until-stable transformation can create cycles between rules,
unbounded execution, and behavior that is difficult to audit.  The security
model instead uses one deterministic ordered transformation followed by a
separate final verification boundary.

### Duplicate Rules

Within one active context, the pair:

```text
matcher type + pattern
```

SHALL identify a unique rule.

A second registration using the same matcher type and the same pattern SHALL be
rejected, regardless of whether the proposed replacement is identical or
different.

This rule prevents re-registration from acting as an implicit mutation operation.
If the original replacement is wrong, the caller should create a new context with
the intended policy rather than silently changing the meaning of the existing
context.

The same pattern text MAY appear under different matcher types because `fixed`,
`glob`, and `ere` intentionally assign different meaning to that text.

### Literal Replacement

Replacement text SHALL remain opaque literal data throughout registration and
application.

No replacement syntax is reserved for:

- matched text;
- capture groups;
- shell expansion;
- command substitution;
- arithmetic expansion;
- escape processing;
- glob expansion;
- regular-expression backreferences;
- or `&`-style substitution.

The library implementation is responsible for neutralizing or avoiding any Bash
mechanism whose native replacement behavior would violate this invariant.

The caller does not escape special replacement characters for bashlog.  If the
replacement contains `$`, `&`, `\`, `*`, `?`, `[`, `]`, parentheses, quotes, or
similar characters, those characters are intended to appear literally in the
redacted output.

### Self-Reintroducing Replacements

A proposed rule SHALL be rejected if its replacement text itself matches the
same rule under the rule's own matcher semantics.

Examples include:

- a `fixed` pattern `secret` with replacement `still-secret-here`;
- a glob pattern whose replacement satisfies that same glob;
- an ERE whose replacement matches that same ERE.

Such a rule is structurally incapable of producing output that satisfies the
final verification requirement for itself.  Rejecting it during registration is
more useful than accepting a rule that will predictably suppress every matching
message later.

This validation does not attempt to solve every interaction between different
rules.  A later rule may still introduce content matching an earlier rule.  The
final verification boundary exists specifically to detect those cross-rule
interactions safely.

## Promises

1. **Matcher type is never guessed.**  Every accepted rule has an explicit
   `fixed`, `glob`, or `ere` interpretation.

2. **Invalid registration does not partially mutate context state.**  A rule is
   appended completely or not at all.

3. **Registration order is preserved exactly.**  Rule ordering does not depend on
   implementation container iteration.

4. **Re-registration is not mutation.**  The same matcher-type/pattern pair cannot
   be registered twice in one context.

5. **Replacement text is always literal.**  Callers do not need a secondary
   escaping language for replacement values.

6. **Empty replacement is intentional removal.**  It is supported as ordinary
   literal data.

7. **One rule does not recursively consume its own inserted replacement during the
   same pass.**  Transformation remains bounded and understandable.

8. **The library does not chase a transformation fixed point.**  Cross-rule
   reintroduction is handled by final verification and fail-closed suppression,
   not unbounded repeated rewriting.

## Non-Promises

1. **Registration order does not imply commutativity.**  Reordering rules may
   change output and is therefore a policy change.

2. **A valid individual rule does not prove that every interaction among rules is
   satisfiable.**  Final verification protects the sink when later rules
   reintroduce protected content.

3. **bashlog does not optimize away apparently redundant rules.**  Accepted order
   and contents are part of the caller-defined policy.

4. **Duplicate rejection is not secret uniqueness across contexts.**  The same
   protected value may legitimately be registered in more than one context.

5. **Literal replacement does not mean the replacement bypasses later rules.**  A
   later registered rule may intentionally match replacement text inserted by an
   earlier rule.

6. **The rule API is not a general-purpose text transformation language.**  It
   intentionally omits captures, backreferences, conditionals, and recursive
   expansion.

## Adversary and Failure Model

### Conditions Intentionally Accounted For

The rule-registration model accounts for:

- a caller accidentally omitting the matcher type;
- an empty pattern;
- an invalid matcher-specific pattern;
- a duplicate registration intended accidentally as an update;
- a different replacement supplied for an already registered pattern;
- replacement strings containing shell or substitution metacharacters;
- a replacement that still matches its own rule;
- implementation refactors that would otherwise reorder associative-array state;
- and cycles that could arise if the full rule set were repeatedly executed until
  no further match existed.

### Conditions Outside the Protection Boundary

The model does not protect against:

- a caller intentionally choosing an overly broad valid pattern;
- a caller deliberately constructing complex interactions among different valid
  rules;
- hostile same-process code modifying internal rule state directly;
- or semantic mistakes where the caller protects the wrong value.

Final verification provides the safety boundary for valid but interacting rules;
it does not claim to make every caller-authored policy useful.

## Operational Constraints

- Every rule MUST explicitly name `fixed`, `glob`, or `ere`.
- Empty patterns MUST be rejected.
- Empty replacements MUST be accepted.
- Rule validation MUST complete before context mutation.
- Failed registration MUST leave context state and rule order unchanged.
- Successful rules MUST be appended in registration order.
- Transformation MUST process rules in registration order.
- Each rule MUST perform one global non-overlapping pass over its current input.
- A rule MUST NOT recursively rescan its own inserted replacement during the same
  pass.
- The entire rule set MUST NOT be repeatedly applied until a fixed point.
- The matcher-type/pattern pair MUST be unique within a context.
- Duplicate registration MUST be rejected rather than treated as update.
- Replacement text MUST remain literal and MUST NOT expose backreference,
  matched-text, expansion, or evaluation semantics.
- A rule whose replacement matches itself under its own matcher semantics MUST be
  rejected.

## Considered Alternatives

### Default to Fixed Matching

Because fixed matching is the strongest and most common secret-redaction mode,
bashlog could treat an omitted matcher type as `fixed`.

It was rejected because explicit matcher selection makes configuration review
clearer and prevents an omitted argument from changing the meaning of a pattern
silently.

### Last Registration Wins

A duplicate matcher/pattern pair could update the replacement in place.

It was rejected because it would create a mutation API hidden inside an append
operation and weaken the monotonic context model established by ADR-020.

### Ignore Exact Duplicates

Identical duplicate rules could be treated as harmless no-ops.

It was rejected because accepting duplicates hides caller mistakes and makes it
harder to distinguish idempotent configuration from repeated registration bugs.
Rejection is clearer and keeps the context definition exact.

### Group Rules by Matcher Type

The implementation could apply all fixed rules, then all globs, then all EREs for
performance or code organization.

It was rejected because grouping changes caller-visible transformation order.
Internal organization must not silently reorder policy.

### Reapply Rules Until Stable

Repeated passes could automatically clean up text reintroduced by later
replacements.

It was rejected because rule cycles can prevent convergence, runtime becomes
unbounded, and the resulting transformation is harder to reason about.  One
ordered pass plus final verification provides a safer architecture.

### Backreference-Capable Replacements

ERE rules could support `\1`, `\2`, or `&` to retain selected matched text.

It was rejected for the redaction API because it creates another expression
language and complicates the guarantee that replacement is opaque data.  A future
transformation API could make a separate decision if a real use case appears.

### Allow Self-Reintroducing Rules and Rely Only on Final Suppression

The final verifier could catch a rule whose replacement still matches itself.

That would remain safe at the sink, but the rule would be predictably unusable for
matching messages.  Early rejection provides a clearer configuration error and
reduces needless runtime suppression.

## Consequences

The registration API is intentionally less permissive than a generic substitution
engine.  That is acceptable because redaction values predictability over text-
processing expressiveness.

Policy order becomes reviewable and testable.  Changing the order requires a new
context rather than hidden mutation.

The implementation must maintain ordered rule storage alongside whatever indexed
structures are useful for validation.  This small amount of additional state is
accepted because ordering is part of the contract.

Matcher implementations must provide a safe `does this text match?` operation as
well as replacement behavior so self-reintroducing replacements and final output
can be validated using the same semantics.

## Source Lineage

This decision refines ADR-018's literal replacement invariant and ADR-020's
append-only context model.  It also follows the project-wide preference for
explicit configuration, deterministic ordering, and failure that leaves state
unchanged.

## Open Questions and Follow-Ups

The exact matching behavior of `fixed`, `glob`, and `ere` is defined in subsequent
ADRs.

The normative specification will define public function names, argument ordering,
return statuses, and diagnostics once the architecture is accepted.

## Related Decisions

- ADR-018: Redaction as an Opt-In Security Boundary
- ADR-019: Readability, Auditability, and Rejection of Obscurity
- ADR-020: Redaction Context Lifecycle and State Model
