# ADR-024: Final Redaction Verification and Fail-Closed Output Boundary

Date: 2026-08-30

## Status

Accepted

## Intent and Documentation Posture

This Architecture Decision Record defines the last security check between
bashlog's rendered output candidate and an actual logging sink.

The project has deliberately chosen an ordered one-pass transformation model for
redaction rules.  That model is bounded and understandable, but ordered
transformations can interact: a later replacement can reintroduce text that
matches an earlier rule.  A correct redaction system therefore needs a final
question that is separate from transformation:

> Does the exact text about to cross the sink boundary still match any active
> redaction rule?

If the answer is yes, or if bashlog cannot answer safely, the text does not cross
the boundary.

This final verification is defense in depth inside the redaction system itself.
It is intentionally redundant with the transformation pass because the cost of a
false negative is disclosure of content the caller explicitly entrusted to
bashlog.

## Context

ADR-017 establishes a common logging pipeline.  ADR-018 establishes that accepted
redaction rules are security obligations and that redaction failure suppresses the
original message.  ADR-021 establishes deterministic registration-order
transformation and rejects repeated fixed-point rewriting.

Those decisions leave one important interaction to resolve.

Consider two rules registered in this order:

```text
1. fixed: SECRET-A -> [A]
2. fixed: marker   -> SECRET-A
```

The first rule can successfully remove every original occurrence of `SECRET-A`.
The second rule can then insert `SECRET-A` again.  If bashlog emits the final text
without rechecking, the first rule's security obligation has been violated even
though its own transformation pass behaved correctly.

The same problem exists across matcher types.  A glob or ERE replacement may
introduce text satisfying an earlier fixed, glob, or ERE rule.  Repeatedly
restarting the entire rule set until no changes occur might eventually remove the
text, but it can also create cycles:

```text
rule A: alpha -> beta
rule B: beta  -> alpha
```

A logging library should not enter an unbounded rewrite loop while handling a
security-sensitive message.

The safer architecture is:

```text
render complete sink-bound candidate
        |
        v
apply each active rule exactly once in registration order
        |
        v
verify final candidate against every active rule
        |
        +-- any rule still matches --> suppress
        |
        +-- verifier cannot decide safely --> suppress
        |
        v
emit
```

The final verification step does not transform.  It answers only whether the
candidate is safe to emit under the active context.

## Decision Drivers

- Ensure later rule replacements cannot reintroduce content protected by earlier
  rules and still reach a sink.
- Preserve bounded one-pass transformation rather than iterative fixed-point
  rewriting.
- Make the final sink security property directly testable.
- Apply protection to complete rendered output, including caller-controlled
  metadata incorporated by bashlog.
- Avoid recursive diagnostics when redaction itself fails.
- Prefer suppression over disclosure when verification is uncertain.
- Use the same matcher semantics for transformation and verification so there is
  no semantic gap between the two phases.

## Decision

Every bashlog logging operation that uses an active redaction context SHALL have a
final redaction verification step immediately before emission.

### Redact the Complete Sink-Bound Candidate

bashlog SHALL complete ordinary message formatting and line rendering before the
final redaction transformation and verification boundary.

The redaction boundary SHALL cover all caller-controlled textual content that
bashlog intends to emit through that logging operation, including, as applicable:

- the formatted message body;
- caller-provided tags or labels;
- caller-provided contextual metadata;
- caller-provided program/component names;
- and other caller-controlled fields incorporated into the rendered line.

Library-owned constant framing such as a fixed severity label is not itself
secret, but placing the redaction boundary over the complete candidate avoids
creating separate bypass paths for metadata.

After final redaction verification succeeds, only sink mechanics that do not
introduce caller-controlled text MAY remain.  For ordinary stdout/stderr output,
that means the final operation should be little more than Bash builtin emission
of the already-approved candidate and its line terminator.

### Ordered Transformation

The active context's rules SHALL first transform the complete rendered candidate
exactly once in registration order according to ADR-021 and the matcher-specific
ADRs.

The result of that ordered pass is a **candidate**, not yet approved output.

### Final Non-Transforming Verification

bashlog SHALL then evaluate the final candidate against **every active rule in the
context** using that rule's own matcher semantics.

The verifier SHALL NOT perform replacement and SHALL NOT attempt to repair the
candidate.

If any fixed, glob, or ERE rule still matches the final candidate, bashlog SHALL
consider redaction incomplete and SHALL suppress the candidate.

If matcher evaluation itself fails or returns an indeterminate/error state,
bashlog SHALL consider verification failed and SHALL suppress the candidate.

Only a candidate for which every active rule produces an unambiguous `no match`
result may cross the logging sink boundary.

This makes the security property explicit:

> A successfully emitted redacted candidate does not match any active rule under
> that rule's documented matcher semantics at final verification time.

### No Fixed-Point Rewriting

A final verification failure SHALL NOT cause bashlog to restart the entire rule
transformation sequence automatically.

The library SHALL suppress rather than repeatedly rewrite until stable.

This prevents cycles, bounds execution, preserves registration-order semantics,
and turns complicated rule interactions into a safe failure instead of a hidden
transformation algorithm.

### Safe Failure Diagnostics

When transformation or final verification fails, bashlog MAY attempt to emit a
fixed library-owned diagnostic such as a message indicating that logging output
was suppressed because redaction failed.

The diagnostic MUST NOT contain:

- the original message;
- the failed final candidate;
- a protected pattern;
- a replacement value if that value could reveal policy contents;
- captured match text;
- or other caller-controlled sink-bound content from the failed operation.

A redaction-failure diagnostic SHALL use a dedicated non-recursive path.  It MUST
NOT call the ordinary logging function in a way that can recursively trigger the
same failing transformation indefinitely.

Before a fixed diagnostic is emitted, bashlog SHOULD verify the diagnostic against
the active context using the same non-transforming matcher checks when that can be
done safely.

If the diagnostic itself matches an active rule, or if its verification cannot be
completed safely, bashlog SHALL prefer silence to disclosure or recursion.

A broad caller-authored pattern can therefore suppress even the fixed failure
diagnostic.  That is an accepted consequence of fail-closed behavior.

### Return Status

Suppression caused by an unknown context, transformation failure, remaining final
match, or verification error SHALL be observable through a non-success return
status.

The exact numeric status belongs to the normative specification and exit-status
contract.  The architectural requirement is that a suppressed security failure
must not masquerade as a successful emission.

### Final Verification and Rule Quality

Final verification is a safety boundary, not a policy linter.

A context containing overly broad but valid rules may suppress many messages.  A
context containing cross-rule interactions may suppress a message after the
ordered pass.  bashlog does not silently weaken or ignore those rules to improve
logging availability.

The caller owns the usefulness of the configured policy; bashlog owns preventing a
candidate that still matches that policy from reaching its sink.

## Promises

1. **Every active rule gets the last word before emission.**  Final candidate text
   is checked against every rule, not only fixed secrets or the most recently
   applied matcher.

2. **Later replacements cannot silently defeat earlier rules.**  If a later rule
   reintroduces protected content, final verification catches the remaining
   match and suppresses output.

3. **The verification phase never repairs by hidden iteration.**  It checks; it
   does not recursively rewrite.

4. **Verification uncertainty fails closed.**  A matcher error is not treated as
   `no match`.

5. **The redaction boundary covers complete caller-controlled rendered output.**
   Message metadata does not receive an intentional bypass path.

6. **Failure diagnostics do not echo the failed content.**  The library does not
   explain a redaction failure by reproducing the thing it refused to emit.

7. **Recursive diagnostic failure is avoided.**  Failure reporting has a dedicated
   bounded path.

8. **Successful redacted emission has a direct negative property.**  At the final
   verification point, no active rule matches the emitted candidate.

## Non-Promises

1. **Final verification does not make a bad policy useful.**  Overly broad rules
   may suppress legitimate logging.

2. **Suppression does not identify which secret would have leaked.**  Diagnostics
   intentionally avoid exposing matching rule details.

3. **The library does not guarantee a visible failure diagnostic.**  If even the
   fixed diagnostic cannot be verified safely, silence is permitted and
   preferred.

4. **Final verification does not protect output paths that bypass bashlog.**  A
   caller printing directly to stdout/stderr remains outside the library boundary.

5. **Final verification is not a secure-memory mechanism.**  It protects the sink,
   not process memory.

6. **The verifier does not perform Unicode normalization or matcher semantics
   beyond the contracts established for fixed, glob, and ERE rules.**

## Adversary and Failure Model

### Conditions Intentionally Accounted For

Final verification is specifically designed to handle:

- a later rule introducing a fixed secret protected by an earlier rule;
- a later rule introducing text matching an earlier glob;
- a later rule introducing text matching an earlier ERE;
- a replacement value colliding with another rule;
- caller-controlled metadata containing a protected value even when the message
  body itself is clean;
- a matcher evaluation error during the final check;
- a malformed or unexpectedly unusable active matcher state;
- a rule cycle that would make iterative-until-stable transformation unsafe;
- and a redaction-failure path tempted to log the original message for diagnosis.

### Conditions Outside the Protection Boundary

The final verifier does not protect against:

- output produced outside bashlog;
- caller-side xtrace before bashlog receives arguments;
- hostile same-process code bypassing or modifying private implementation state;
- values that do not match any configured rule;
- or semantically sensitive data the caller never registered or described with a
  matching rule.

## Operational Constraints

- Redaction MUST operate on the complete rendered sink-bound candidate containing
  all caller-controlled textual fields bashlog intends to emit.
- Every active rule MUST be applied once in registration order during
  transformation.
- After transformation, every active rule MUST be evaluated again in a
  non-transforming verification pass.
- Final verification MUST use the same matcher semantics as transformation.
- Any remaining match MUST suppress the candidate.
- Any verification error or indeterminate matcher result MUST suppress the
  candidate.
- bashlog MUST NOT restart the entire rule set automatically after final
  verification failure.
- Only a candidate with `no match` from every active rule may be emitted.
- A redaction-failure diagnostic MUST NOT contain original or failed candidate
  text or secret-bearing rule content.
- Failure diagnostics MUST use a bounded non-recursive path.
- If a failure diagnostic cannot itself be verified safely, bashlog MUST prefer
  silence.
- Redaction-related suppression MUST return a non-success status.
- Sink mechanics after successful verification MUST NOT introduce new
  caller-controlled textual content.

## Considered Alternatives

### Verify Only Fixed Secrets

Because fixed rules represent known exact secrets, bashlog could provide the
strong final guarantee only for them.

It was rejected because ADR-018 treats every accepted rule as a security
obligation according to its matcher semantics.  A later replacement can
reintroduce text matching a glob or ERE just as easily as it can reintroduce a
fixed value.

### Trust Each Rule's Own Transformation Pass

If every rule globally replaces its matches, the library could emit immediately
after the last rule.

It was rejected because later rules can reintroduce earlier protected content.
The per-rule transformations are locally correct but insufficient to prove the
final sink property.

### Reapply Rules Until No Matches Remain

The library could keep transforming until a complete pass makes no changes.

It was rejected because caller-authored rules can cycle, runtime becomes
unbounded, and output meaning becomes a fixed-point computation rather than the
explicit registration-order policy.  Suppression is safer and easier to audit.

### Emit the Original Message with an Error Prefix

A logging library may prefer observability and print something such as
`REDACTION FAILED: <original message>`.

It was rejected by ADR-018.  The original message is the exact content that may
contain the protected value; reproducing it in the failure path defeats the
security boundary.

### Emit the Failed Candidate for Debugging

Because most redaction may already have succeeded, printing the candidate could
help identify the problematic rule interaction.

It was rejected because the final verifier exists specifically because the
candidate is not proven safe.  Printing unverified candidate text is logically
identical to bypassing the verifier.

### Always Emit a Fixed Failure Diagnostic Without Verification

A constant message contains no original secret and appears safe.

It was rejected as an unconditional guarantee because callers may configure very
broad glob or ERE rules that match the constant diagnostic itself.  The safer
contract permits the diagnostic only when it can pass a bounded verification
check; otherwise silence is acceptable.

## Consequences

Every redacted log operation performs additional matcher work after the
transformation pass.  Runtime cost grows with the number and complexity of active
rules.

That cost is accepted.  bashlog is a logging library with an explicit security
boundary, not a high-throughput binary regex engine.  Preventing an entrusted
secret from crossing a sink is more important than avoiding one additional
bounded verification pass.

Some valid rule combinations will suppress messages rather than produce output.
This is also accepted.  The caller can create a corrected new context when policy
interactions are undesirable; bashlog does not weaken rules automatically.

Tests gain a strong invariant to assert: after a successful redacted logging call,
no active matcher may match the emitted candidate.

The implementation must maintain a dedicated failure-reporting path that is
simple enough to reason about without ordinary logger recursion.

## Source Lineage

This decision completes the fail-closed redaction boundary established by
ADR-018 and resolves the earlier open question about whether final fixed-secret
verification is required.

The decision intentionally generalizes the final check to all active matcher types
because the security obligation belongs to accepted rules, not only to one
implementation category.

It also follows ADR-019's auditability requirement by choosing one bounded ordered
pass plus one bounded verification pass instead of iterative hidden rewriting.

## Open Questions and Follow-Ups

The normative specification defines the public suppression status, fixed safe
diagnostic wording, context-selection syntax, and fully silent failure behavior.
Implementation tests must cover cross-rule reintroduction across all matcher-type
combinations that are practical to construct.

## Related Decisions

- ADR-017: Logging Pipeline, Levels, Formatting, and Emission
- ADR-018: Redaction as an Opt-In Security Boundary
- ADR-019: Readability, Auditability, and Rejection of Obscurity
- ADR-020: Redaction Context Lifecycle and State Model
- ADR-021: Redaction Rule Registration, Ordering, and Replacement Semantics
- ADR-022: Fixed-String Redaction and Multibyte Guarantees
- ADR-023: Glob and ERE Redaction Semantics
