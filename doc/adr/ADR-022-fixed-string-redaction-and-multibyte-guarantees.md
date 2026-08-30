# ADR-022: Fixed-String Redaction and Multibyte Guarantees

Date: 2026-08-30

## Status

Accepted

## Intent and Documentation Posture

This Architecture Decision Record defines the strongest redaction matcher in
bashlog: `fixed`.

Fixed matching is the mode intended for known sensitive values such as passwords,
API keys, bearer tokens, session identifiers, private identifiers, and other
literal strings whose exact value is already available to the caller.

The project deliberately gives this matcher a stronger and more portable contract
than glob or ERE matching.  A caller who already knows the exact value to protect
should not have to reason about wildcard syntax, regular-expression metacharacters,
locale-sensitive character classes, capture groups, or pattern-engine edge cases.

## Context

The simplest redaction problem is also the most common:

```text
known secret value -> replace every exact occurrence before output
```

For example, if a caller registers:

```text
hunter2
```

with replacement:

```text
[REDACTED PASSWORD]
```

then every exact occurrence of `hunter2` in sink-bound text should be replaced by
those literal replacement characters.

The word "exact" needs clarification in Bash because strings may contain UTF-8 or
other multibyte sequences, locale can affect pattern engines, and visually
identical Unicode text can have distinct encoded representations.

The project does not need Unicode normalization to make fixed redaction useful.
In normal application flow, the sensitive value stored in a variable is the same
sequence later interpolated into a message.  Matching that exact sequence is a
strong and testable guarantee.

Bash also has a fundamental string limitation: shell variables and command
arguments cannot represent embedded NUL bytes as ordinary string content.  The
library must not imply that it can redact values the runtime cannot faithfully
represent.

Finally, implementation convenience must not weaken literal semantics.  Bash
parameter substitution treats its pattern operand as a shell pattern, and newer
Bash versions can assign meaning to characters such as `&` in replacements.
Even if the eventual implementation uses parameter expansion internally, it must
neutralize those semantics so callers receive literal fixed matching and literal
replacement.

## Decision Drivers

- Provide the strongest redaction guarantee for exact known secrets.
- Make fixed matching independent of regular-expression syntax and wildcard
  interpretation.
- Support exact multibyte values without requiring ASCII-only secrets.
- Avoid claiming Unicode normalization or semantic-equivalence behavior the
  library does not implement.
- Preserve literal replacement semantics on every supported Bash version.
- Keep behavior deterministic and testable under Bash 4.3.
- Make the implementation readable enough to audit.
- State the NUL limitation explicitly rather than implying arbitrary binary-data
  support.

## Decision

The `fixed` matcher SHALL interpret its pattern as opaque literal Bash string
content.

No character in a fixed pattern SHALL acquire glob, ERE, shell-expansion,
escape, or other metasyntactic meaning.

Characters including the following are ordinary literal data in fixed patterns:

```text
* ? [ ] ( ) { } . ^ $ + | \ ' " ` ; & < >
```

The list is illustrative rather than exhaustive.  The architectural rule is that
**all representable pattern characters are literal**.

### Exact Occurrence Semantics

A fixed rule SHALL replace every non-overlapping exact occurrence of its pattern
in the current input for that rule.

Matching SHALL proceed deterministically from left to right.

When possible occurrences overlap, replacement of the leftmost occurrence
consumes the characters participating in that match.  Matching then continues
after the consumed occurrence.  The implementation does not need to preserve an
overlapping occurrence whose characters were already consumed by a prior match.

For example, with pattern `aba` and input:

```text
ababa
```

the leftmost `aba` is replaced.  The overlapping occurrence that began inside
those already-consumed characters is not treated as a second independent match.

This is ordinary non-overlapping global replacement behavior and keeps runtime
bounded and predictable.

### Literal Multibyte Matching

Fixed matching SHALL support exact multibyte strings that Bash can represent.

If a caller registers a fixed pattern containing UTF-8 accented characters,
Cyrillic, CJK characters, emoji, combining marks, or other multibyte content, and
the same exact string sequence later appears in sink-bound text, bashlog SHALL
redact that exact sequence.

The guarantee is about exact representation, not visual or linguistic
equivalence.

For example, a precomposed character and a visually equivalent decomposed
sequence are distinct fixed strings unless the caller registers both forms.

bashlog SHALL NOT normalize fixed patterns or messages to NFC, NFD, NFKC, NFKD,
or another Unicode normalization form as part of the initial architecture.

bashlog SHALL NOT perform locale-sensitive case folding for fixed matching.

### Locale Independence of Fixed Semantics

The meaning of a fixed rule SHALL NOT intentionally change because the caller
changes `LC_ALL`, `LC_CTYPE`, `LANG`, or another locale setting.

The implementation may necessarily use Bash string operations whose internal
handling is influenced by the runtime, but the public semantic contract remains
literal equality of the exact supplied string, not locale-defined equivalence.

If an implementation technique cannot preserve that contract on a supported Bash
version, the technique must be changed or the compatibility decision revisited;
the public contract must not silently degrade into pattern semantics.

### NUL Bytes

bashlog SHALL explicitly document that fixed rules operate on Bash strings and do
not support embedded NUL bytes.

This is a Bash runtime limitation, not a special redaction parser restriction.
The library does not claim binary-safe matching for values that cannot be
represented faithfully in shell variables or arguments.

### Fixed Matching Is the Recommended Mode for Known Secrets

Documentation SHALL recommend `fixed` when the caller has the exact sensitive
value.

Glob and ERE exist for structural patterns, not because they are preferable ways
to represent an already known literal secret.

This recommendation matters for security reasoning: fixed rules have the least
interpretation, the narrowest match semantics, and the strongest multibyte
contract.

### Implementation Independence

This ADR defines behavior, not a required replacement algorithm.

The implementation MAY use parameter expansion, slicing, iterative scanning, or
another pure-Bash technique if and only if the resulting behavior satisfies the
literal contract.

The implementation MUST NOT expose native pattern or replacement semantics merely
because a concise Bash construct happens to provide them.

In particular, any use of `${parameter//pattern/replacement}` or related
constructs must account for:

- escaping pattern metacharacters so the fixed value remains literal;
- preserving literal replacement characters;
- Bash-version differences in replacement handling;
- multibyte behavior;
- and auditability of the escaping algorithm.

If a shorter implementation is harder to prove correct than an explicit scan,
ADR-019 requires choosing the implementation that is easier to inspect.

## Promises

1. **Every fixed pattern character is literal.**  No shell-pattern or ERE syntax
   is active inside a fixed rule.

2. **Every exact non-overlapping occurrence is replaced during that rule's pass.**
   Matching is deterministic and left-to-right.

3. **Exact multibyte values are supported.**  A representable multibyte string
   supplied as the pattern is protected when that exact same sequence appears in
   the candidate output.

4. **Fixed matching does not intentionally depend on locale-defined character
   classes, wildcard semantics, or regular-expression behavior.**

5. **Replacement remains literal.**  Fixed matching does not weaken ADR-018 or
   ADR-021 replacement guarantees.

6. **Known secrets have a matcher with minimal interpretation.**  Callers do not
   need to regex-escape or glob-escape an exact secret before registration.

7. **The NUL limitation is disclosed.**  bashlog does not pretend Bash strings are
   arbitrary binary buffers.

## Non-Promises

1. **No Unicode normalization equivalence.**  Visually equivalent but differently
   encoded strings are not assumed to be the same fixed value.

2. **No case-insensitive matching.**  `Secret` and `secret` are distinct fixed
   values unless both are registered.

3. **No transliteration, canonicalization, or whitespace normalization.**  Fixed
   means exact.

4. **No embedded-NUL support.**  Bash cannot faithfully represent that data in the
   ordinary string interfaces bashlog consumes.

5. **No protection for transformed variants the caller did not register.**  If a
   secret is URL-encoded, base64-encoded, hashed, truncated, normalized, or
   otherwise transformed before logging, the original fixed rule does not
   automatically identify that different representation.

6. **No secure-memory claim.**  The fixed plaintext must remain available to
   bashlog while the active rule exists, subject to ADR-018 and ADR-020.

## Adversary and Failure Model

### Conditions Intentionally Accounted For

The fixed matcher is designed to handle:

- secrets containing regex metacharacters;
- secrets containing glob metacharacters;
- secrets containing shell metacharacters;
- secrets containing `$`, `&`, backslashes, brackets, quotes, or parentheses;
- repeated occurrences in one log line;
- adjacent occurrences;
- exact multibyte UTF-8 values;
- multibyte characters before or after the secret;
- combining sequences when the logged sequence is exactly the registered
  sequence;
- and implementations tempted to use pattern-oriented Bash constructs for
  convenience.

### Conditions Outside the Protection Boundary

The fixed matcher does not claim to handle:

- different Unicode normalization forms automatically;
- case variants automatically;
- encoded or transformed variants automatically;
- embedded NUL bytes;
- or content that never reaches bashlog in the exact registered representation.

## Operational Constraints

- `fixed` patterns MUST be treated as literal strings.
- Fixed patterns MUST NOT enable glob, ERE, expansion, or escape semantics.
- Fixed matching MUST replace all non-overlapping exact occurrences in a rule
  pass.
- Matching MUST be deterministic and left-to-right.
- Exact representable multibyte strings MUST be supported.
- Fixed matching MUST NOT promise Unicode normalization equivalence.
- Fixed matching MUST NOT intentionally become locale-sensitive pattern
  matching.
- Documentation MUST recommend `fixed` for known exact secret values.
- Documentation MUST disclose that embedded NUL bytes are outside Bash string
  support.
- Implementation techniques MUST neutralize any native Bash pattern or
  replacement semantics that would violate the fixed contract.
- Implementation readability MUST take precedence over concise but difficult-to-
  audit shell tricks.

## Considered Alternatives

### Treat Fixed Patterns as Shell Globs After Escaping by the Caller

The library could document an escaping convention and require callers to prepare
literal values for Bash pattern substitution.

It was rejected because the caller already supplied literal data.  Requiring a
secondary escaping language transfers implementation risk to every consumer and
makes secret registration easier to get wrong.

### Normalize Unicode Before Matching

Normalization could make visually equivalent representations match automatically.

It was rejected for the initial architecture because Bash has no native Unicode
normalization primitive at the compatibility floor, external helpers violate the
runtime boundary, and normalization can change application data in ways that are
far broader than exact secret protection.

### Case-Insensitive Fixed Matching

Case-insensitive matching might protect case-varying identifiers.

It was rejected because passwords, tokens, keys, and most secret values are
case-sensitive.  Case folding would broaden the match surface and introduce
locale questions without helping the core exact-secret use case.

### Byte-Oriented Binary Matching

A library could attempt to treat strings as arbitrary byte buffers.

It was rejected because ordinary Bash variables cannot represent embedded NUL
bytes.  Claiming binary-safe behavior would exceed the runtime's actual model.

### Use ERE for All Matching

Every fixed string could be escaped into a regular expression and processed by
one matcher engine.

It was rejected because regex escaping becomes part of the security-critical path,
locale and ERE semantics become relevant unnecessarily, and the implementation
would be harder to audit for the most common exact-secret case.

## Consequences

The fixed matcher needs its own implementation path or a carefully isolated
literalization layer rather than blindly reusing glob or ERE machinery.

That duplication is acceptable because the semantics are materially different and
because fixed matching carries the strongest security promise.

Tests must include an intentionally broad set of metacharacter and multibyte
fixtures.  Testing only ASCII alphanumeric secrets would not exercise the
contract established here.

The library documentation can give clear guidance: when the exact value is known,
use `fixed`; use pattern matchers only when the value is structural rather than
known literally.

## Source Lineage

This decision refines ADR-018's fixed-secret discussion and the project's earlier
agreement that exact multibyte values should be supported without claiming
Unicode normalization.

It also follows ADR-019's requirement that security-sensitive behavior remain
plainly inspectable rather than hiding literalization behind clever shell
metaprogramming.

## Open Questions and Follow-Ups

The exact pure-Bash replacement algorithm remains an implementation decision to be
validated against this contract and the Bash 4.3 floor.

If implementation experiments demonstrate that Bash 4.3 requires materially more
fragile or opaque code than a newer Bash release, ADR-002 should be revisited
explicitly rather than weakening this matcher contract.

Final output verification across all matcher types is governed by a separate ADR.

## Related Decisions

- ADR-002: Bash Runtime and Portability Baseline
- ADR-018: Redaction as an Opt-In Security Boundary
- ADR-019: Readability, Auditability, and Rejection of Obscurity
- ADR-020: Redaction Context Lifecycle and State Model
- ADR-021: Redaction Rule Registration, Ordering, and Replacement Semantics
