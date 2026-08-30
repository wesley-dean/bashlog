# ADR-019: Readability, Auditability, and Rejection of Obscurity

Date: 2026-08-30

## Status

Accepted

## Intent and Documentation Posture

This ADR establishes readability and auditability as architectural requirements
for bashlog, especially in code that handles redaction state or controls the last
boundary before log output.

The project explicitly rejects security through obscurity.  Deliberately making
state, control flow, or sensitive operations difficult to follow would conflict
with the trust model being built around observable behavior, explicit limits,
and reviewable guarantees.

This decision is not merely a style preference.  A security-sensitive path that
is hard to understand is harder to verify, harder to test correctly, harder to
modify safely, and easier to misunderstand during incident response or future
maintenance.

## Context

Bash permits many forms of cleverness:

- indirect variable expansion;
- nameref chains;
- dynamically generated variable names;
- `eval`;
- generated function definitions;
- compact parameter-expansion tricks;
- encoded state;
- dense one-liners;
- command-string construction;
- and naming conventions designed to discourage inspection.

Some of these facilities have legitimate uses.  None should be selected merely
because they make implementation state harder for a human to inspect.

This matters acutely for redaction.  A reviewer should be able to answer basic
security questions from ordinary source review:

- Where are registered rules stored?
- Which state contains plaintext fixed secrets?
- How is each rule type matched?
- In what order are rules applied?
- Can a registered secret leave the Bash process through a bashlog-controlled
  path?
- Can diagnostics reproduce the original message or rule data?
- What happens when matching fails?
- What happens when output fails?
- Can any logging level or convenience helper bypass redaction?
- Does replacement text receive interpretation?
- Which assumptions depend on Bash version or locale?

If answering those questions requires deobfuscation, generated-code inspection,
an LLM, tracing through `eval`, or reconstructing encoded state, the
implementation has failed an architectural requirement even if tests currently
pass.

The project also needs to remain honest about the difference between internal
convention and actual isolation.  Prefixing an implementation variable with
`__bashlog_` can communicate "not public API."  It does not make the variable
private from other code executing in the same shell.

Trying to hide that variable behind a cryptic name does not improve the security
boundary.  It only makes the code harder to audit.

## Decision Drivers

- Make security-sensitive behavior understandable to ordinary Bash developers.
- Ensure trust can be based on inspection and tests rather than hidden machinery.
- Avoid security theater that adds complexity without creating real isolation.
- Make future code review effective even when the original authors are absent.
- Reduce the chance that AI-assisted changes preserve tests while violating the
  intended security model.
- Keep internal state ownership and lifecycle obvious.
- Prefer explicit transformations over compact but opaque shell tricks.
- Keep the security-critical path small enough to reason about directly.
- Preserve clear distinction between public API, internal convention, and actual
  runtime protection.

## Decision

bashlog SHALL treat readability, inspectability, and auditability as correctness
properties for security-sensitive implementation.

The project SHALL prefer explicit, plainly named state and straightforward
control flow over cleverness, compression, or obscurity when those goals
conflict.

Security-sensitive internal state SHOULD use descriptive names that communicate
its purpose.  For example, structures conceptually similar to:

```text
__bashlog_redact_rule_types
__bashlog_redact_rule_patterns
__bashlog_redact_rule_replacements
```

are preferable to short or deliberately mangled identifiers whose primary effect
is to hide meaning.

The exact internal data structure remains an implementation decision until the
redaction-context ADR is accepted.  The naming principle is binding regardless
of structure.

bashlog SHALL NOT use obfuscation, reversible encoding, obscure naming, or
indirection as a claimed security control for same-process state.

bashlog SHALL NOT use `eval` in the security-critical logging or redaction path
unless a future ADR demonstrates that no clearer mechanism can satisfy a
necessary requirement and explicitly revises this decision.  The current design
anticipates no such need.

Runtime generation of function definitions, secret-dependent variable names, or
code strings SHALL NOT be used to create an appearance of encapsulation.

Namerefs and indirect expansion MAY be used where they materially improve clear,
idiomatic Bash implementation, but they MUST NOT be stacked or used in ways that
make state ownership difficult to trace.  A direct array lookup is preferable to
an indirect mechanism when both solve the problem comparably.

The security-critical path SHOULD consist of small functions with single,
documented responsibilities.  A reviewer should be able to follow the path from
formatted message to redaction to final output by reading the maintained source
and generated development artifact without specialized tooling.

Doxygen documentation SHALL explain non-obvious Bash semantics, quoting
requirements, ordering assumptions, locale dependencies, and failure behavior
where those details affect security or correctness.

The implementation SHALL not compress security-critical code merely to make the
maintained source or release artifact shorter.  The build system already provides
comment-stripped and minified consumer artifacts; maintainers are therefore free
to optimize source for understanding.

Tests SHALL complement, not replace, auditability.  Passing tests do not justify
an implementation that future reviewers cannot reasonably understand.

## Promises

1. **The security path is intended to be inspectable.**  A competent Bash
   developer should be able to understand how sink-bound text is redacted and
   emitted without specialized reverse-engineering tools.

2. **Internal state is plainly described.**  Names and documentation communicate
   purpose rather than intentionally concealing it.

3. **No security claim relies on obscurity.**  bashlog does not claim that a
   secret is protected because its variable name is hard to guess, encoded, or
   buried behind indirection.

4. **Internal conventions are labeled honestly.**  `__bashlog_*` communicates
   implementation detail, not private memory or access control.

5. **Security-relevant complexity must justify itself.**  Shorter or more clever
   code is not automatically better when it increases the reasoning burden.

6. **Documentation accompanies non-obvious semantics.**  Bash behaviors that are
   material to safety or correctness are explained near the implementation using
   the project's exact Doxygen documentation model.

## Non-Promises

1. Readable code does not make the runtime immune to defects.

2. Auditability does not replace automated tests, peer review, static analysis,
   or security review.

3. Descriptive internal names do not prevent same-process code from reading or
   modifying those variables.

4. Avoiding obfuscation does not mean every internal function becomes public API.
   Public compatibility remains defined by documented namespaced interfaces.

5. The project does not promise that every implementation detail will be obvious
   to a Bash beginner.  Some behavior, particularly pattern matching and locale
   interaction, may require careful explanation.

6. The project does not reject every Bash feature that involves indirection.  It
   rejects unnecessary indirection that makes important behavior harder to
   reason about.

## Adversary and Failure Model

This decision addresses maintenance and assurance failures including:

- a developer assuming an encoded secret is meaningfully protected;
- a future maintainer treating a cryptic variable name as a privacy boundary;
- security-sensitive behavior implemented through `eval` or generated code that
  is difficult to inspect;
- a dense one-liner passing tests while hiding edge-case behavior;
- AI-assisted refactoring preserving output examples while changing an
  undocumented invariant;
- a reviewer overlooking that a convenience helper bypasses the central
  redaction path;
- a future optimization changing replacement interpretation or ordering;
- implementation comments that restate syntax but fail to record the reason an
  unusual construct is necessary;
- and incident responders being unable to determine quickly where protected data
  could leave the library.

This ADR does not address malicious same-process code by trying to hide state from
it.  Such concealment would not create a meaningful boundary in Bash.

The design instead assumes that maintained bashlog code should be reviewable by
a potentially skeptical reader who has access to all source.  The system should
remain defensible under that level of inspection.

## Operational Constraints

- Security-sensitive code MUST favor explicitness and readability over
  obfuscation or compression.
- Internal security-sensitive state SHOULD use descriptive `__bashlog_*` names.
- Documentation MUST NOT describe internal naming conventions as private memory
  or access control.
- Obscure names, reversible encoding, or hidden indirection MUST NOT be used as a
  claimed security control.
- `eval` MUST NOT be used in the logging/redaction security path under the current
  architecture.
- Runtime-generated function definitions MUST NOT be used to implement the core
  logging or redaction path.
- Indirect expansion and namerefs MUST be used conservatively and MUST NOT make
  state ownership or data flow materially harder to trace.
- Security-critical functions SHOULD remain small and responsibility-focused.
- Doxygen comments MUST explain non-obvious security-relevant Bash semantics and
  assumptions.
- Maintained source MUST NOT be compressed merely to reduce consumer artifact
  size.
- Review MUST consider auditability separately from whether tests happen to pass.

## Considered Alternatives

### Obscure Internal Variable Names

Cryptic names could make it less likely that application developers casually
notice or use internal redaction state.

It was rejected because accidental API use should be discouraged through
namespacing and documentation, not through deliberate opacity.  A malicious or
curious same-process caller can enumerate shell state anyway, while maintainers
pay the readability cost permanently.

### Reversibly Encode Stored Secrets

Base64 or custom encoding could prevent plaintext from being immediately visible
in a simple variable dump.

It was rejected because bashlog would need to reverse the encoding to perform
matching, so the information remains available to same-process code.  The
encoding would add implementation and testing complexity while encouraging an
inflated security claim.

### Hash Stored Secrets

Hashing appears stronger than reversible encoding.

It was rejected as a redaction storage strategy because a hash cannot directly
locate its plaintext preimage inside arbitrary message text.  Generic candidate
substring hashing would be complex and impractical, low-entropy secrets remain
guessable, and SHA-256 is not natively available at the current Bash floor.

### Use Process Isolation to Create a Stronger Boundary

A separate process could own redaction state and communicate with the caller.

It was rejected for the initial design because the IPC, synchronization, failure,
signal, buffering, and lifecycle complexity would make the system substantially
harder to understand while still not providing a full secure-memory boundary.
The architecture prioritizes a smaller, honest boundary.

### Use Metaprogramming to Reduce Repetition

Generated wrappers, array accessors, or rule handlers could reduce source length.

It was rejected where the reduction would obscure the actual API or security
flow.  Repetition in small explicit functions is acceptable when it makes
behavior easier to review.

### Rely Primarily on Tests Instead of Source Clarity

A sufficiently exhaustive suite could theoretically establish behavior without
requiring every reviewer to understand the implementation.

It was rejected because tests are necessarily selective and can encode the same
misunderstanding as the implementation.  For a library whose trust model invites
inspection, source comprehension is itself valuable evidence.

## Consequences

Maintained source may be longer than a highly compressed Bash implementation.
That is intentional and is already supported by the three-artifact build model.

Code review may reject changes that are behaviorally correct but unnecessarily
opaque.  Contributors should expect questions such as "Can this be written more
directly?" to carry architectural weight in security-sensitive areas.

The design may occasionally choose a few additional lines, explicit loops, or
named intermediate variables over compact parameter-expansion expressions.  The
tradeoff is accepted when it improves assurance.

This ADR also creates a useful standard for future security review: auditability
is not documentation placed around an inscrutable implementation; it is a
property the implementation itself must preserve.

## Source Lineage

This decision consolidates the project's explicit rejection of security through
obscurity and builds on documentation and readability practices already used in
bashdeps, Bootstrap, mktext, adrctl, bash-doxygen, and template-bash.

It is especially aligned with ADR-007's "more is more" Doxygen posture and
ADR-018's requirement that redaction guarantees be based on observable behavior
rather than vague trust claims.

## Open Questions and Follow-Ups

- The concrete redaction implementation should be reviewed explicitly against
  this ADR after feasibility experiments are complete.
- If Bash 4.3 requires substantially more opaque code than Bash 5.2 for a
  security-critical operation, the runtime floor should be reconsidered rather
  than forcing a clever compatibility workaround.
- The project may eventually define a lightweight manual security-review
  checklist based on the questions in this ADR.

## Related Decisions

- ADR-001: Documentation and Decision Hierarchy
- ADR-007: Doxygen-Based Verbose Source Documentation Standard
- ADR-008: Documentation-Driven, Test-Second Development
- ADR-013: Sourceable Library Scope and Responsibility Boundary
- ADR-014: Pure Bash Runtime and External Command Boundary
- ADR-015: Namespaced Public API and Caller-Owned Convenience Wrappers
- ADR-017: Logging Pipeline, Levels, Formatting, and Emission
- ADR-018: Redaction as an Opt-In Security Boundary
