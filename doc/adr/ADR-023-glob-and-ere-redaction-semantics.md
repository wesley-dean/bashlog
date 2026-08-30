# ADR-023: Glob and ERE Redaction Semantics

Date: 2026-08-30

## Status

Accepted

## Intent and Documentation Posture

This Architecture Decision Record defines the two pattern-oriented redaction
matchers provided by bashlog: `glob` and `ere`.

These matchers exist for cases where a caller cannot or does not want to enumerate
every exact protected value.  They intentionally provide more expressive matching
than `fixed`, and that expressiveness introduces more environmental and semantic
complexity.

The project therefore makes a deliberately narrower portability promise for glob
and ERE matching than it makes for fixed strings.  Pattern-oriented rules use
Bash's own pattern and regular-expression semantics, remain case-sensitive, and
are explicitly affected by the current locale where Bash itself defines
locale-sensitive behavior.  They do not receive an invented Unicode abstraction
that Bash does not provide.

## Context

Some sensitive data is structural rather than known as one literal value.
Examples include:

- account or tax identifiers with a stable shape;
- structured tokens whose complete value is not available when policy is
  configured;
- path-like or host-like strings where wildcard structure is useful;
- or application-specific fields recognizable by a regular expression.

A fixed matcher cannot express those cases without registering every concrete
value.

Bash provides two native pattern systems relevant to the problem:

1. shell pattern matching, commonly described as glob matching; and
2. POSIX-style extended regular expressions through `[[ string =~ regex ]]`.

Using Bash-native matchers supports ADR-014's no-external-command runtime boundary
and keeps implementation within the language users can inspect directly.

However, these matchers have properties that must be made explicit:

- wildcard and bracket syntax changes the meaning of pattern characters;
- locale can affect ranges, character classes, and regular-expression behavior;
- extended glob syntax can depend on shell options;
- regular expressions can be invalid;
- both matcher families can express patterns that match the empty string;
- ERE capture groups exist even though bashlog replacement strings do not support
  backreferences;
- and global replacement requires a bounded strategy that does not loop forever
  on zero-length matches.

The project must define these boundaries before implementation chooses convenient
but accidental semantics.

## Decision Drivers

- Provide useful structural redaction without external tools.
- Reuse recognizable Bash matching semantics rather than inventing a custom
  pattern language.
- Keep matching case-sensitive and deterministic with respect to documented
  inputs.
- Prevent zero-length matching from causing loops or ambiguous global replacement.
- Prevent the caller's `extglob` setting from silently changing the supported
  pattern language.
- Validate ERE syntax before a rule becomes active.
- Preserve literal replacement semantics even when ERE capture groups are used
  for matching.
- Be honest about locale and multibyte limitations.
- Retain the Bash 4.3 floor unless implementation evidence demonstrates that the
  guarantees cannot be met clearly there.

## Decision

bashlog SHALL support `glob` and `ere` as explicit matcher types in addition to
`fixed`.

Both matcher types SHALL be case-sensitive.

Neither matcher SHALL perform pathname expansion or access the filesystem.
Patterns operate only on in-memory candidate text.

### Glob Semantics

`glob` SHALL use Bash's basic shell pattern-matching semantics for:

- `*`;
- `?`;
- bracket expressions such as `[abc]` and ranges/classes recognized by Bash;
- and ordinary literal pattern characters according to Bash pattern rules.

Extended-glob operators such as:

```text
?(...)
*(...)
+(...)
@(...)
!(...)
```

SHALL NOT be part of the initial bashlog glob language.

A proposed glob rule containing extended-glob operator syntax SHALL be rejected
rather than interpreted differently depending on the caller's `extglob` shell
option.

bashlog SHALL NOT enable, disable, or otherwise modify the caller's `extglob`
setting merely to implement redaction.

The public glob contract is therefore intentionally smaller than every pattern
form Bash can support in every shell configuration.

### Glob Match Selection

A glob rule SHALL perform global non-overlapping replacement over substrings of
the current candidate text.

Matching SHALL proceed from left to right.  At the leftmost position where the
pattern can match, if more than one match length is possible, the longest match at
that position SHALL be selected.

The matched substring is replaced with the rule's literal replacement and the
rule continues after the consumed input characters.  Replacement text inserted by
the current rule is not recursively rescanned by that same rule during the same
pass, consistent with ADR-021.

This contract is intentionally aligned with Bash's pattern-substitution model
without adopting Bash's replacement-string interpretation.

### Glob Patterns That Match Empty Text

A glob rule SHALL be rejected if its pattern is capable of matching the empty
string.

For the supported basic glob language, a registration-time empty-string match
check SHALL be part of validation.

This rejects degenerate rules such as a bare `*` and any other supported pattern
that can succeed without consuming input.

The restriction is not a statement that empty-string matching is invalid in Bash.
It is a bashlog safety rule: global redaction requires every accepted match to
consume at least one input character so progress is provable.

### ERE Semantics

`ere` SHALL use the extended regular-expression semantics provided by Bash's
`[[ string =~ regex ]]` operator.

The regular expression SHALL be supplied and stored as data.  bashlog SHALL NOT
use `eval`, construct shell source from the pattern, or interpret regex text as
Bash code.

ERE grouping and capture syntax MAY be used to describe what text matches.  Any
capture information exposed internally through `BASH_REMATCH` is implementation
state only.

Capture groups SHALL NOT create replacement semantics.  `\1`, `\2`, `&`, and
similar text in a bashlog replacement remain literal characters as required by
ADR-018 and ADR-021.

### Invalid EREs

A proposed ERE rule SHALL be validated before it is appended to an active
context.

If Bash reports the expression as syntactically invalid, registration SHALL fail
and context state SHALL remain unchanged.

The implementation MUST distinguish:

- valid expression that does not match the validation input;
- valid expression that matches;
- and invalid expression.

It MUST NOT treat an invalid ERE as equivalent to `no match` and accept the rule.

If an already accepted ERE later cannot be evaluated safely during a logging
operation, that logging operation fails closed under the final verification and
failure rules.

### EREs That Can Match Empty Text

An ERE rule SHALL be rejected if it can match the empty string.

Registration validation SHALL test the proposed ERE against empty input using the
same Bash ERE engine.  An expression that successfully matches empty input is not
accepted as a redaction rule.

This rejects expressions such as those built entirely from optional or zero-or-
more constructs, anchors that require no consumed characters, and other forms
capable of zero-length success.

The requirement exists because global replacement needs a monotonic input cursor.
A successful match that consumes zero characters can otherwise produce infinite
loops or ambiguous progress rules.

### ERE Global Replacement

An ERE rule SHALL replace every non-overlapping match in one bounded pass.

Matching proceeds left-to-right using Bash ERE semantics.  Each successful match
MUST consume at least one character because zero-length-capable expressions are
rejected.

The implementation must reconstruct prefix, matched text, and remaining input
without confusing an identical matched value later in the string with the match
Bash actually selected.

This is a known implementation challenge under Bash 4.3 because `BASH_REMATCH`
provides matched strings rather than portable explicit byte offsets.  The project
will not weaken semantics merely to obtain a shorter implementation.

If experiments show that a correct, bounded, and auditable implementation cannot
be produced under the Bash 4.3 floor, ADR-002 SHALL be revisited explicitly before
implementation proceeds.

### Locale and Multibyte Behavior

Glob and ERE matching SHALL use the caller's current Bash locale environment at
the time of the redaction operation.

bashlog SHALL NOT silently force `LC_ALL=C`, switch locales, or capture and restore
a private locale merely to make pattern behavior appear more portable.

As a consequence, bracket ranges, character classes, collation, and other
locale-sensitive pattern behavior may differ across environments according to
Bash and the underlying locale implementation.

Documentation SHALL state this limitation directly.

bashlog SHALL NOT promise Unicode normalization, Unicode property matching,
grapheme-cluster semantics, or identical glob/ERE multibyte behavior across all
locales.

Callers requiring protection of one exact known multibyte secret SHOULD use the
`fixed` matcher, whose stronger exact-sequence contract is defined in ADR-022.

### Caller Shell Options

Sourcing bashlog SHALL not modify caller `shopt` or shell-option state under
ADR-013.

The implementation MUST avoid allowing optional shell features to silently expand
the documented glob or ERE language.

If a caller option would otherwise change an implementation technique's semantics,
bashlog must insulate the public behavior or choose a different technique rather
than mutate caller state.

## Promises

1. **Glob means documented basic Bash pattern syntax, not pathname expansion.**
   Matching occurs only against in-memory log text.

2. **Extglob is not an ambient hidden dependency.**  The supported glob language
   does not change because the caller enabled or disabled `extglob`.

3. **Glob replacement is bounded and non-overlapping.**  It proceeds left-to-right
   and uses the longest match at a selected leftmost position.

4. **ERE means Bash ERE semantics.**  bashlog does not invent a subtly different
   regular-expression dialect while calling it ERE.

5. **Invalid EREs are rejected before activation.**  Syntax errors do not become
   silent no-match behavior.

6. **Every accepted pattern match consumes input.**  Glob and ERE patterns capable
   of matching the empty string are rejected.

7. **Capture groups never change replacement semantics.**  Replacement remains
   literal data.

8. **Locale dependence is disclosed rather than hidden.**  Pattern matching uses
   the caller's current locale and does not claim stronger Unicode portability.

9. **bashlog does not change caller shell options to implement patterns.**

## Non-Promises

1. **No locale-independent glob/ERE equivalence.**  Pattern behavior can differ
   where Bash or libc locale rules differ.

2. **No Unicode normalization.**  Pattern matching does not canonicalize text.

3. **No Unicode-property regex engine.**  bashlog exposes Bash ERE behavior, not
   PCRE, Perl, or a Unicode-specific engine.

4. **No lookaround, backreference replacement, or external-regex extensions.**
   Features not present in Bash ERE are not added by bashlog.

5. **No extglob.**  Advanced shell wildcard operators are deliberately outside the
   initial contract.

6. **No protection from an overly broad valid pattern.**  bashlog can validate
   structural safety but cannot know whether a caller's pattern expresses the
   intended business meaning.

7. **No guarantee that pattern matchers are preferable to fixed matching for known
   secrets.**  They are more expressive and correspondingly more complex.

## Adversary and Failure Model

### Conditions Intentionally Accounted For

The matcher design accounts for:

- invalid ERE syntax;
- patterns that can match zero characters;
- caller `extglob` differences;
- ERE capture groups that might tempt a replacement-language implementation;
- multiple and repeated matches;
- identical matched substrings occurring more than once;
- locale-dependent bracket or character-class behavior;
- and an implementation that might otherwise invoke `sed`, `grep`, `awk`, or
  another external matcher for convenience.

### Conditions Outside the Protection Boundary

The design does not claim to neutralize:

- semantically incorrect but syntactically valid caller patterns;
- differences among installed locales that Bash itself exposes;
- Unicode normalization differences;
- unsupported regex features a caller assumes are present;
- or hostile same-process modification of internal accepted patterns.

## Operational Constraints

- `glob` MUST use the documented basic Bash pattern language.
- Extglob operators MUST NOT be supported in initial glob rules.
- bashlog MUST NOT change the caller's `extglob` setting.
- Glob replacement MUST be global, non-overlapping, left-to-right, and longest at
  the selected leftmost position.
- Glob patterns capable of matching empty input MUST be rejected.
- `ere` MUST use Bash `[[ =~ ]]` ERE semantics.
- ERE pattern text MUST remain data and MUST NOT be evaluated as shell source.
- Invalid EREs MUST be rejected before context mutation.
- EREs capable of matching empty input MUST be rejected.
- ERE replacement MUST be global, non-overlapping, bounded, and left-to-right.
- ERE capture groups MUST NOT create replacement backreferences.
- Glob and ERE behavior MUST be documented as locale-sensitive where Bash defines
  locale-sensitive matching.
- bashlog MUST NOT force or mutate caller locale or shell-option state to implement
  these matchers.
- Documentation SHOULD recommend `fixed` for exact known multibyte secrets.

## Considered Alternatives

### Support Extglob Automatically

bashlog could honor advanced Bash wildcard operators whenever the caller has
`extglob` enabled.

It was rejected because the same registered rule would mean different things in
different caller shell states.  Enabling extglob inside the library would also
violate the sourceable-library side-effect boundary.

### Force Extglob On Temporarily

The library could snapshot, enable, use, and restore the caller's option.

It was rejected because sourceable security-sensitive code should not depend on
mutating ambient parser/matcher configuration when the required feature is not
necessary for the initial use cases.

### Force the C Locale

Running patterns under `LC_ALL=C` would reduce some locale variability.

It was rejected because it would change caller-observable semantics, weaken
multibyte expectations, and create hidden locale mutation.  The project prefers
to document Bash's actual pattern boundary.

### Use an External Regex Tool

`sed`, `perl`, `grep`, or `awk` could make global regex replacement easier.

It was rejected by ADR-014.  More importantly for the security model, it would
send unredacted candidate text and patterns across a process boundary that the
library has explicitly chosen not to create.

### Accept Zero-Length Patterns with a Special Progress Rule

The implementation could force the cursor forward by one character after a
zero-length match.

It was rejected because the resulting replacement semantics are surprising,
matcher-specific, and easy to get wrong around multibyte text.  Redaction does not
need zero-length matches to express meaningful protected content.

### Provide PCRE-Like Syntax

A custom or external PCRE layer would offer richer matching.

It was rejected because it would either require an external dependency or a large
custom parser, neither of which is justified for a small auditable Bash library.

## Consequences

Pattern-oriented rules are intentionally more environment-dependent than fixed
rules.  Documentation and tests need to preserve that distinction rather than
present all three matchers as interchangeable.

The implementation must include explicit validation for extglob constructs,
empty-string capability, and ERE syntax.

ERE global replacement is one of the most technically demanding pieces of the
library under Bash 4.3.  Implementation work should begin with focused feasibility
experiments and tests.  If the correct solution becomes clever or fragile, the
project should reconsider the runtime floor or matcher scope rather than hiding
complexity behind sparse comments.

## Source Lineage

This decision refines the matcher families reserved by ADR-018 and follows the
fixed-string contrast established by ADR-022.

It also applies ADR-013's no-source-time-shell-mutation rule and ADR-019's demand
for explicit, auditable security-critical implementation.

## Open Questions and Follow-Ups

Implementation experiments must confirm the exact Bash 4.3 behavior used for
leftmost/longest glob and ERE global replacement and encode that behavior in the
Bats suite.

If Bash 4.3 cannot support the documented ERE behavior without opaque machinery,
ADR-002 should be revisited before code is accepted.

Final verification after all rule transformations is defined separately.

## Related Decisions

- ADR-002: Bash Runtime and Portability Baseline
- ADR-013: Sourceable Library Scope and Responsibility Boundary
- ADR-014: Pure Bash Runtime and External Command Boundary
- ADR-018: Redaction as an Opt-In Security Boundary
- ADR-019: Readability, Auditability, and Rejection of Obscurity
- ADR-021: Redaction Rule Registration, Ordering, and Replacement Semantics
- ADR-022: Fixed-String Redaction and Multibyte Guarantees
