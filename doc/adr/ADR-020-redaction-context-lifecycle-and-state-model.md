# ADR-020: Redaction Context Lifecycle and State Model

Date: 2026-08-30

## Status

Accepted

## Intent and Documentation Posture

This Architecture Decision Record defines the lifecycle, naming, mutability, and
failure semantics of bashlog redaction contexts.

The decision is intentionally detailed because a redaction context is not merely
a convenient container for strings.  Once a caller has registered a rule in a
context and asks bashlog to use that context, the context participates in the
security boundary established by ADR-018.  Ambiguity about whether a context was
created, whether it can be weakened, whether a typo silently disables redaction,
or whether destruction means secure erasure would create precisely the kind of
false confidence the project is trying to avoid.

The context model therefore favors monotonic state, explicit failure, and a
small number of lifecycle transitions that can be understood by reading ordinary
Bash.

## Context

A logging library needs some way to group redaction rules.  A single global rule
set would be easy to implement, but it would make unrelated applications or
subsystems share policy and would make it difficult to express that one logging
operation should use one set of protected values while another operation uses a
different set.

Named contexts solve that problem.  A caller may define a context for a logical
security boundary such as `auth`, `database`, `api-client`, or `request_42` and
then select that context when logging data governed by those rules.

The context mechanism itself introduces questions that must be answered before
implementation:

- Does a context need an explicit create operation?
- Can an empty context exist?
- Does adding the first rule implicitly create the context?
- Can rules be edited, reordered, or removed?
- Can new rules be added after the context has already been used?
- Does first use seal the context?
- Can a context be destroyed?
- Can a destroyed name be reused?
- What happens if a logging call names a context that does not exist?
- What names are legal?
- Is a context name sensitive data?
- Does destroying a context imply that the underlying secret bytes have been
  securely erased from Bash memory?

These questions are not implementation trivia.  They determine whether a caller
can reason about the effective redaction policy and whether configuration errors
fail safe.

Bash also places practical constraints on context identifiers.  Associative-array
subscripts and other indirect shell constructs have historically had subtle
expansion behavior across Bash versions.  bashlog has no useful requirement for
arbitrary shell syntax in a context name.  Permitting command-substitution
characters, quoting syntax, newlines, or other complex text would therefore
increase parsing and audit burden without increasing meaningful capability.

## Decision Drivers

- Make the active redaction policy easy to reason about over time.
- Prevent a typo in a requested context name from silently disabling redaction.
- Avoid mutation operations that can weaken an already-trusted context in place.
- Allow applications to add secrets that become known only after startup.
- Avoid requiring a separate empty-context creation step with no security value.
- Provide a way to stop using a context and release bashlog-owned references
  without making an unsupported secure-erasure claim.
- Keep context identifiers deliberately boring and safe to use in Bash data
  structures.
- Avoid public context operations whose primary purpose is to reveal registered
  secret material.
- Preserve the Bash 4.3 compatibility floor unless a concrete implementation
  requirement justifies changing it.

## Decision

bashlog SHALL use named redaction contexts with a deliberately small lifecycle.

A context has one of three logical states during a Bash process:

```text
unseen -> active -> destroyed
```

There is no transition from `destroyed` back to `active` for the same context
name during the same Bash process.

### Context Creation

bashlog SHALL NOT require a separate public `create empty context` operation.

The first **successful** addition of a redaction rule to a previously unseen
context SHALL create that context and make it active atomically with the rule
addition.

A failed attempt to add a rule MUST NOT create a partially initialized or empty
active context.

As a consequence, every active redaction context contains at least one accepted
rule.

This model avoids an ambiguous state where a caller creates a context, assumes it
provides protection, but forgets to register any actual redaction rule.

### Context Names

Public context names SHALL be non-empty ASCII identifiers matching the following
conceptual grammar:

```text
[A-Za-z_][A-Za-z0-9_.:-]*
```

The normative specification MAY express the validation algorithm without relying
on an external regular-expression command, but it MUST preserve the same accepted
character set unless a later ADR changes the contract.

The restricted grammar is intentional.  Context names are identifiers, not
arbitrary user content.  They do not need whitespace, shell quoting, command
substitution, glob syntax, regular-expression syntax, Unicode normalization, or
control characters.

Context names MAY appear in diagnostics because they are treated as non-secret
metadata.  Callers MUST NOT place secret values in context names and expect the
context-name field itself to provide secret storage.

### Append-Only Active Contexts

An active context SHALL be append-only.

A caller MAY add additional valid redaction rules to an active context at any time
before destruction, including after the context has already been used for logging.
This supports applications that discover credentials, tokens, identifiers, or
other protected values during runtime rather than only during initialization.

An active context SHALL NOT support operations that:

- modify an existing rule in place;
- change an existing rule's matcher type;
- change an existing rule's pattern;
- change an existing rule's replacement;
- reorder existing rules;
- remove one individual rule;
- or replace the whole rule set while retaining the same context identity.

The redaction policy for an active context can therefore become stronger or more
comprehensive by appending rules, but bashlog does not provide an in-place
operation whose purpose is to weaken or reinterpret previously accepted rules.

When a caller needs materially different policy, it SHOULD create a new context
by adding the first rule under a new name and deliberately switch logging to that
new context.

Versioned or purpose-specific names such as `auth_v1`, `auth_v2`, or
`request_42` are preferable to hidden mutation when policy identity matters.

### No Automatic Sealing

Using a context for logging SHALL NOT automatically seal it against later rule
addition.

Automatic sealing was considered but rejected because runtime-discovered secrets
are common and because append-only addition does not weaken rules that were
already trusted.

A future explicit sealing feature would require a separate decision demonstrating
that it solves a real problem without creating a second overlapping lifecycle
model.

### Whole-Context Destruction

bashlog SHALL provide a one-way operation that destroys an active context as a
bashlog policy object.

Destruction SHALL:

- make the context unavailable for future redaction use;
- remove bashlog-owned active references to that context's rule data where the
  implementation can do so;
- record enough non-secret state to prevent the same context name from being
  recreated during the same Bash process;
- and cause future attempts to use or modify that context to fail.

Destruction SHALL operate on the entire context.  It is not a mechanism for
removing selected rules while preserving the rest of the context.

The project SHALL use language such as `destroy`, `forget`, or `release
references` carefully.  The operation MUST NOT be documented as secure deletion,
secure zeroization, memory wiping, cryptographic destruction, or proof that the
secret no longer exists anywhere in Bash memory.

Bash may have copied string contents internally, and bashlog cannot prove that
all historical copies have been overwritten.  Context destruction means that
bashlog intentionally stops retaining and using the active policy through its
own data structures; it does not manufacture a secure-memory guarantee that the
runtime does not provide.

### Unknown and Destroyed Contexts

Redaction remains opt-in.  A logging operation that does not request a redaction
context MAY proceed without redaction according to the surrounding logging
contract.

Once a caller explicitly asks bashlog to use a named redaction context, however,
that request becomes part of the security decision.

If the requested context:

- has never been successfully created by rule registration;
- was destroyed;
- has an invalid identifier;
- or otherwise cannot be resolved as an active context;

bashlog SHALL fail closed for that logging operation.  It MUST NOT interpret an
unknown context as an empty rule set and emit the original message unchanged.

The original sink-bound message MUST be suppressed.  A safe fixed diagnostic MAY
be emitted according to the final redaction-failure rules established elsewhere,
but the message itself cannot be used as diagnostic content.

### Public Introspection

bashlog SHALL NOT provide a public operation whose purpose is to retrieve the
patterns, replacements, or secret-bearing rule contents stored in a context.

Non-sensitive metadata such as `context exists`, `context destroyed`, or a rule
count MAY be considered later if a concrete use case justifies it and the
interface cannot reveal protected rule contents.  Such metadata is not required
for the initial architecture.

## Promises

1. **A context is never silently empty after creation.**  The first accepted rule
   creates the active context atomically; failed registration does not create an
   empty active object.

2. **Active context policy is monotonic.**  Existing rules are not edited,
   reordered, or individually removed through the public API.

3. **Runtime-discovered secrets remain possible.**  Additional rules may be
   appended after a context has been used.

4. **An explicitly requested unknown context does not disable redaction
   silently.**  The corresponding logging operation fails closed.

5. **Destroyed context names are not reused in the same process.**  A caller that
   needs new policy uses a new context identity.

6. **Destruction removes bashlog's active policy references as far as the
   implementation can intentionally control.**  The destroyed context is no
   longer usable through bashlog.

7. **Context naming is predictable.**  Context identifiers use a restricted ASCII
   grammar rather than arbitrary shell text.

8. **No public context API reproduces secret-bearing rules.**  Context management
   does not introduce a supported secret-exfiltration interface.

## Non-Promises

1. **Context destruction is not secure erasure.**  bashlog cannot prove that Bash
   or the operating system no longer contains historical copies of a value.

2. **Context names are not secret storage.**  They may appear in diagnostics and
   should contain identifiers, not credentials.

3. **An active context is not immutable.**  It may gain additional rules over
   time.  The promise is append-only policy, not frozen policy.

4. **bashlog does not infer the correct context.**  The caller remains responsible
   for selecting the context appropriate to the logging operation.

5. **No-context logging is not automatically protected.**  Redaction is opt-in;
   a caller that chooses no context receives no context-based redaction guarantee.

6. **Same-process code is not prevented from inspecting internal state.**  The
   absence of public getters is an API design decision, not process-level access
   control.

7. **The context grammar is not an internationalized naming system.**  The
   restricted ASCII identifier is deliberately narrower than arbitrary human
   text.

## Adversary and Failure Model

### Conditions Intentionally Accounted For

The context model is designed to handle:

- a typo in a context name used by a logging call;
- a failed first rule registration;
- repeated attempts to add invalid rules;
- a need to add a newly discovered secret after logging has already begun;
- a maintainer who might otherwise mutate or delete one rule in a trusted context;
- a caller that destroys a context and later accidentally tries to reuse it;
- shell metacharacters or expansion syntax supplied as a proposed context name;
- and confusion between releasing bashlog-owned references and securely erasing
  process memory.

### Conditions Outside the Protection Boundary

The context model does not protect against:

- malicious same-process code directly modifying bashlog's internal variables;
- a caller deliberately bypassing validation by invoking private implementation
  functions;
- debugger or privileged memory inspection;
- the caller choosing the wrong **valid** context for semantic reasons bashlog
  cannot know;
- or secret values the caller intentionally places in a context name despite the
  documented contract.

## Operational Constraints

- Context lifecycle MUST be `unseen -> active -> destroyed`.
- The first successful rule addition MUST create an active context atomically.
- Failed first rule registration MUST NOT leave an empty active context.
- Active contexts MUST contain at least one accepted rule.
- Context names MUST follow the restricted ASCII identifier grammar.
- Active contexts MUST be append-only.
- Individual rules MUST NOT be modified, reordered, or removed through the public
  API.
- Using a context MUST NOT automatically seal it against future rule additions.
- Whole-context destruction MUST make the context unusable and MUST prevent reuse
  of the same name during the same Bash process.
- Destruction MUST NOT be described as secure erasure or zeroization.
- An explicitly requested unknown, invalid, or destroyed context MUST fail closed
  and MUST NOT be treated as an empty rule set.
- Logging without a requested redaction context MAY remain unredacted because
  redaction is opt-in.
- The public API MUST NOT expose secret-bearing context rule contents.

## Considered Alternatives

### One Global Redaction Rule Set

A global rule set would reduce API surface and eliminate context selection.

It was rejected because unrelated callers and subsystems would share one policy,
policy identity would be unclear, and applications could not intentionally scope
sets of secrets to distinct logging flows.

### Explicit Empty-Context Creation

A `create` operation could establish a context before any rules exist.

It was rejected because an empty active context creates little value and creates a
new failure mode: a caller may believe that naming the context provides
protection even though no actual rule was registered.  First successful rule
addition is a more meaningful creation boundary.

### Mutable Rules

The API could support `set`, `replace`, `unset`, or reorder operations for
individual rules.

It was rejected because mutable policy makes it harder to answer what an already
trusted context means at a particular point in execution.  New policy can be
expressed by appending stronger rules or by creating a new context identity.

### Seal on First Use

A context could become immutable after the first logging call that uses it.

This was attractive because policy would become frozen once trusted.  It was
rejected because applications commonly learn secrets at runtime and because
append-only additions strengthen rather than remove previous protections.  The
cost in flexibility was not justified.

### Reuse a Destroyed Context Name

A destroyed name could return to the unseen state and be recreated.

It was rejected because reuse makes lifecycle history ambiguous and can make a
stale reference unexpectedly become valid again.  A new policy should use a new
name.

### Individual Rule Deletion

Selective deletion would allow expired secrets to stop consuming memory or
matching log messages.

It was rejected because it weakens a trusted context in place and invites a false
secure-erasure interpretation.  Whole-context destruction provides a cleaner
lifecycle boundary.  A caller needing a reduced rule set can create a new context.

### Arbitrary String Context Names

Allowing all Bash strings as names would maximize flexibility.

It was rejected because context names are identifiers, not payload data.  Shell
metacharacters, whitespace, control characters, and expansion syntax increase
implementation and audit complexity without providing meaningful logging value.

## Consequences

Callers that need to replace or weaken policy must use a new context rather than
editing an old one.  This may create more names over a long-running process, but
it makes policy transitions visible and reviewable.

Applications can still register secrets discovered later because active contexts
remain appendable until destruction.

The implementation must maintain a small amount of non-secret tombstone state for
destroyed context names if name reuse is to be prevented.  That cost is accepted
because it prevents stale references from unexpectedly becoming valid again.

The context identifier grammar is intentionally narrower than arbitrary Bash
strings.  This is a feature: the reduced input surface makes associative-array and
indirect-state code easier to audit under the Bash 4.3 compatibility floor.

## Source Lineage

This decision specializes the context-based redaction model discussed in
ADR-018 and follows the broader bashlog principles of explicit state, narrow
interfaces, fail-closed security behavior, and refusal to claim runtime guarantees
that Bash cannot provide.

The append-only model also follows the project family's preference for additive,
inspectable configuration over hidden mutation.

## Open Questions and Follow-Ups

The exact public function names and return-status values belong in the normative
specification once the related rule-registration ADRs are accepted.

Rule type semantics, duplicate detection, ordering, fixed-string guarantees,
glob/ERE behavior, and final verification are intentionally governed by
subsequent ADRs rather than being embedded here.

## Related Decisions

- ADR-013: Sourceable Library Scope and Responsibility Boundary
- ADR-015: Namespaced Public API and Caller-Owned Convenience Wrappers
- ADR-018: Redaction as an Opt-In Security Boundary
- ADR-019: Readability, Auditability, and Rejection of Obscurity
