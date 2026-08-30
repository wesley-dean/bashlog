# bashlog Public Behavior Specification

Status: Draft

Date: 2026-08-30

## Purpose

This document defines the intended observable public behavior of bashlog.

Architecture Decision Records under `doc/adr/` explain why consequential design
choices exist.  This specification translates those choices into a concrete
public contract: function names, argument ordering, outputs, return statuses,
level semantics, redaction-context selection, and failure behavior.

The specification is intentionally precise.  A caller should not have to inspect
implementation details to determine what a public function means, and an
implementer should not have to invent public semantics while writing code.

This document is currently **Draft** because ADR-013 through ADR-024 remain in
Proposed status and the runtime implementation has not yet been written.  The
specification therefore describes the contract proposed for the first functional
release.  It MUST NOT be represented as already-implemented behavior until tests
and implementation demonstrate the contract.

## Normative Language

The terms MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT, and MAY are used
normatively.

Where this specification conflicts with an Accepted ADR, the ADR governs and the
conflict must be corrected.  Where this specification depends on a Proposed ADR,
the behavior remains provisional until the governing ADR is accepted.

## Runtime Baseline

bashlog targets Bash 4.3 or newer.

Normal runtime operation uses Bash language facilities and builtins only.  The
library does not invoke external commands for loading, level handling, message
formatting, redaction, rendering, verification, or emission.

Development, build, test, documentation, and release tooling are outside this
consumer runtime boundary.

## Source-Time Contract

Sourcing the distributed bashlog library SHALL define the documented namespaced
API and initialize only bashlog-owned runtime state required for that API.

Sourcing bashlog MUST NOT:

- write to standard output;
- write to standard error;
- install or replace traps;
- enable or disable `set` shell options;
- enable or disable `shopt` options;
- define generic functions such as `debug`, `info`, `warn`, `error`, or `die`;
- define aliases;
- invoke `export -f`;
- access the network;
- invoke external commands;
- inspect Git state;
- discover application configuration from files;
- or assume application error-handling or exit policy.

The implementation may create clearly namespaced Bash variables and functions.
Internal `__bashlog_*` names are implementation details by convention and are not
private or access-controlled by Bash.

## Public API Overview

The proposed initial public API is deliberately narrow:

```text
bashlog_level_get
bashlog_level_set

bashlog_log
bashlog_debug
bashlog_info
bashlog_notice
bashlog_warning
bashlog_error
bashlog_critical
bashlog_alert
bashlog_emergency

bashlog_redaction_add
bashlog_redaction_context_destroy
bashlog_redact
```

No other function participates in the stable public contract merely because it
exists in the generated artifact.

The first stable release SHOULD treat documented `bashlog_*` functions as
semantic-version compatibility surface.  `__bashlog_*` functions and variables
MUST NOT be treated as stable interfaces.

## Return Statuses

The initial API uses a small, shared status vocabulary.  The values intentionally
follow familiar `sysexits` numeric conventions where that improves recognition,
but bashlog does not depend on a system `sysexits.h` file or external utility.

| Status | Meaning |
| ---: | --- |
| `0` | The requested operation succeeded.  For logging calls, this also includes intentional suppression by the configured level threshold. |
| `64` | The caller supplied invalid arguments, an invalid level, an invalid context identifier, an unknown option, or otherwise invalid API syntax. |
| `65` | A proposed redaction rule is invalid, duplicate, unsatisfiable, or cannot be accepted under its matcher contract. |
| `69` | A specifically requested redaction context is unavailable because it is unknown or destroyed. |
| `70` | Redaction, final verification, or another internal security-sensitive transformation could not be completed safely. |
| `74` | A final logging emission to standard error failed. |

Public functions MUST NOT use a non-zero status merely because a message was
suppressed by log-level policy.  Routine threshold suppression is successful
logging policy, not an application error.

Functions MAY return a more specific status from this table when multiple failure
categories are possible.  The implementation MUST document each public function's
actual subset in its Doxygen block.

## Severity Model

bashlog uses the conventional eight syslog severity levels and their numeric
ordering:

| Number | Canonical name | Public helper |
| ---: | --- | --- |
| `0` | `emergency` | `bashlog_emergency` |
| `1` | `alert` | `bashlog_alert` |
| `2` | `critical` | `bashlog_critical` |
| `3` | `error` | `bashlog_error` |
| `4` | `warning` | `bashlog_warning` |
| `5` | `notice` | `bashlog_notice` |
| `6` | `info` | `bashlog_info` |
| `7` | `debug` | `bashlog_debug` |

The public contract uses the full canonical names above.  Short aliases such as
`warn`, `err`, `crit`, `emerg`, `panic`, `fatal`, `success`, and `dbg` are not part
of the initial namespaced API.

Applications MAY define their own wrappers.  For example:

```bash
warn() {
  bashlog_warning "$@"
}

error() {
  bashlog_error "$@"
}
```

Those generic names remain application-owned.

### Threshold Semantics

The active threshold is a severity number from `0` through `7`.

A message is eligible for emission when:

```text
message severity <= active threshold
```

The default threshold is `info` (`6`).

Therefore the default configuration permits emergency, alert, critical, error,
warning, notice, and info messages while suppressing debug messages.

A threshold of `0` permits only emergency messages.  A threshold of `7` permits
all defined severities.

Threshold suppression occurs before `printf`-style message construction.  This
avoids unnecessary creation and copying of a message that will not cross a
bashlog sink.

Syntax and explicitly requested context validity are still caller contract.  A
logging call with invalid API syntax or an explicitly requested unavailable
redaction context MUST NOT silently become successful merely because its severity
would otherwise be suppressed.

## `bashlog_level_get`

### Synopsis

```text
bashlog_level_get
```

### Behavior

Writes the active canonical severity name to standard output followed by one
newline.

Example output:

```text
info
```

### Return Status

- `0`: level written successfully.

The function takes no arguments.  Supplying arguments returns `64` and writes no
level value to standard output.

## `bashlog_level_set`

### Synopsis

```text
bashlog_level_set LEVEL
```

### Accepted Level Values

`LEVEL` may be either:

- a canonical severity name: `emergency`, `alert`, `critical`, `error`,
  `warning`, `notice`, `info`, or `debug`; or
- the corresponding integer `0` through `7`.

Names are case-sensitive in the initial API.  Aliases are not accepted.

### Behavior

On success, the active threshold changes for subsequent logging calls in the
current Bash process.  The function produces no standard output or standard
error output.

On failure, the previous threshold remains unchanged.

### Return Status

- `0`: threshold changed.
- `64`: missing, extra, or invalid level argument.

## Logging Call Syntax

The generic logger and every severity helper use the same message-call shape.

### Generic Logger

```text
bashlog_log LEVEL [--context CONTEXT] [--] FORMAT [ARGUMENT ...]
```

### Severity Helpers

```text
bashlog_info [--context CONTEXT] [--] FORMAT [ARGUMENT ...]
bashlog_warning [--context CONTEXT] [--] FORMAT [ARGUMENT ...]
```

The same shape applies to every severity helper listed above.

`--context CONTEXT` selects one active redaction context for this call.

`--` explicitly ends bashlog option parsing.  It is required when the intended
format string begins with `-` or could otherwise be interpreted as a bashlog
option.  It MAY be used unconditionally for clarity.

Only `--context` and `--` are recognized as logging-call options in the initial
API.  Unknown options return `64` without emitting the caller's message.

A logging call that omits `--context` performs no context-based redaction.  This
is intentional because redaction is opt-in.

There is no ambient or implicit "current redaction context" in the initial API.
Context choice is explicit at each logging call that requires redaction.

## `printf`-Style Message Construction

`FORMAT` and subsequent arguments use Bash builtin `printf` formatting semantics.
The implementation SHALL construct the message in shell state before rendering
or emission.

Callers SHOULD use a literal format and pass arbitrary data as arguments:

```bash
bashlog_info 'user=%s status=%s' "${user}" "${status}"
```

When caller-controlled text itself should be logged literally, callers SHOULD
use `%s`:

```bash
bashlog_info '%s' "${untrusted_text}"
```

Using arbitrary caller data as the `FORMAT` argument gives that data `printf`
format semantics and is outside bashlog's promise to treat the format string as
literal data.

A formatting error returns `64` and the caller's message is not emitted.

Bash variables cannot faithfully represent embedded NUL bytes.  bashlog therefore
does not promise logging or redaction behavior for data requiring embedded NUL.

## Rendered Log Format

The initial rendered form is deliberately minimal:

```text
LEVEL: MESSAGE
```

where `LEVEL` is the canonical lowercase severity name.

Examples:

```text
info: application started
warning: configuration is deprecated
error: connection failed
```

bashlog appends exactly one newline after the rendered candidate when emitting it.
The message itself is otherwise preserved according to Bash string semantics and
the configured redaction transformations.

The initial renderer does not automatically add:

- timestamps;
- hostnames;
- process identifiers;
- application names;
- Git revisions;
- colors;
- syslog facilities;
- or tags.

Callers that require such data may construct it themselves and pass it as message
data.  If caller code invokes an external command to acquire that information,
the caller owns that external-command boundary.

Embedded newlines and other representable control characters in a message are not
escaped or normalized by the initial renderer.  Callers requiring single-line or
log-injection-resistant message normalization must perform that transformation
before calling bashlog.  This limitation SHOULD be revisited only through an
explicit behavioral or architectural decision rather than silent sanitization.

## Logging Output Stream

All public logging functions emit their final log record to **standard error**.

This applies to every severity.  bashlog does not use standard output for normal
logging because standard output is commonly an application's data channel in
shell programs, pipelines, and command substitutions.

A caller may redirect standard error using ordinary Bash redirection.

The initial API does not provide:

- built-in file sinks;
- caller-selected file-descriptor configuration;
- syslog emission;
- network sinks;
- or external-command sinks.

Those capabilities require separate review because every new sink participates in
the final redaction boundary.

## Logging Pipeline

For a syntactically valid call, the observable processing model is:

```text
validate call and requested context
    -> severity/threshold decision
    -> printf-style message construction
    -> render canonical severity and message
    -> apply selected context's rules in registration order, if any
    -> perform final verification against every active rule in that context
    -> emit to standard error
```

No caller-controlled sink-bound text is appended after final redaction
verification.

A threshold-suppressed call returns `0` and emits nothing.

## Redaction Context Selection

A logging call requests redaction only by specifying:

```text
--context CONTEXT
```

The context name must match:

```text
[A-Za-z_][A-Za-z0-9_.:-]*
```

A requested context must already be active.

If a logging call explicitly names a context that is invalid, unknown, or
destroyed:

- the caller's rendered message MUST NOT be emitted;
- the operation returns `64` for an invalid identifier or `69` for an unknown or
  destroyed valid identifier;
- a fixed safe diagnostic MAY be written as defined below.

An omitted context is different from an unavailable requested context.  Omission
means "perform this logging operation without context-based redaction."  An
unavailable requested context means the caller attempted to rely on a policy that
bashlog cannot provide, so the call fails closed.

## `bashlog_redaction_add`

### Synopsis

```text
bashlog_redaction_add CONTEXT MATCHER PATTERN REPLACEMENT
```

### Matchers

`MATCHER` MUST be exactly one of:

```text
fixed
glob
ere
```

Matcher names are case-sensitive.

### Context Creation

If `CONTEXT` is unseen, the first successful rule addition creates it atomically.
There is no separate public empty-context creation operation.

If rule validation fails, an unseen context remains unseen.

If `CONTEXT` is already active, the successfully validated rule is appended.

If `CONTEXT` was destroyed, registration returns `69` and the name cannot be
reused during the current Bash process.

### Rule Ordering

Rules are applied in exact successful registration order.

The public API does not modify, reorder, replace, or individually remove active
rules.

### Duplicate Rules

A context MUST NOT contain two rules with the same matcher type and identical
pattern bytes.

Attempting to register such a duplicate returns `65`; the existing rule remains
unchanged and no new rule is appended.

### Empty Values

An empty pattern is invalid and returns `65`.

An empty replacement is valid and means that each match is removed.

### Replacement Semantics

Replacement text is always opaque literal data.

Characters such as the following have no replacement-language meaning:

```text
&
\1
$()
${NAME}
*
?
[
]
```

bashlog does not provide backreferences, matched-text substitution, parameter
expansion, command substitution, escape processing, or code evaluation in
replacement strings.

A rule whose replacement itself satisfies that same rule's matcher is rejected
with `65` because the rule is predictably incapable of satisfying final
verification on its own replacement.

### Return Status

- `0`: rule appended successfully; an unseen context becomes active.
- `64`: invalid argument count, invalid context identifier, or unknown matcher
  name.
- `65`: invalid pattern, invalid ERE, zero-length-capable pattern, duplicate rule,
  self-matching replacement, or another rule-level validation failure.
- `69`: context name is a destroyed context tombstone.

The function produces no standard output on success.

A failure diagnostic MUST NOT reproduce the pattern or replacement.

## `fixed` Matcher

`fixed` is the preferred matcher for known passwords, tokens, API keys, and other
exact sensitive values.

Every pattern character is literal.  Glob and ERE metacharacters have no special
meaning.

Every non-overlapping exact occurrence is replaced from left to right.

For overlapping possible matches, the leftmost match is replaced and processing
continues after that matched input.  For example, fixed pattern `aaa` against
`aaaaa` replaces the first three characters and leaves the final two unless a
later rule also matches them.

Exact representable multibyte strings are supported.  This includes ordinary
UTF-8 text such as accented Latin characters, Cyrillic, CJK text, and emoji when
the caller and shell environment represent the same byte sequence.

`fixed` does not perform:

- Unicode normalization;
- canonical-equivalence matching;
- case folding;
- locale-insensitive semantic matching;
- glob interpretation;
- or ERE interpretation.

If a protected value was registered in one Unicode normalization form and the log
contains a distinct byte sequence that renders similarly, bashlog does not claim
that the values are equivalent.

## `glob` Matcher

`glob` uses the deliberately limited basic Bash glob pattern language defined by
ADR-023.

The initial contract supports ordinary Bash pattern elements such as:

- `*`;
- `?`;
- bracket expressions such as `[abc]` and `[[:digit:]]` as understood by Bash in
  the caller's current locale.

Extended glob operators such as `@(...)`, `+(...)`, `*(...)`, `?(...)`, and
`!(...)` are not supported.  A proposed pattern containing extglob operator
syntax is rejected rather than having meaning depend on ambient `shopt -s
extglob` state.

A glob pattern capable of matching an empty string is rejected with `65`.

Glob behavior that Bash itself defines through the current locale remains
locale-sensitive.  bashlog does not modify the caller's locale.

## `ere` Matcher

`ere` uses Bash `[[ STRING =~ ERE ]]` extended regular-expression semantics.

The pattern is data supplied to Bash's ERE matcher.  bashlog does not add a second
regular-expression replacement language.

An invalid ERE is rejected during registration with `65`.

An ERE capable of matching an empty string is rejected with `65` so global
redaction cannot enter a zero-length match loop or ambiguous progression model.

ERE capture groups may participate in matching according to Bash, but capture
groups do not create replacement backreferences.  Replacement remains literal.

ERE matching follows Bash/libc locale semantics where applicable.  bashlog does
not promise Unicode normalization or locale-independent character-class meaning.

## One-Pass Rule Application

Each active rule receives one bounded global, non-overlapping transformation pass
in registration order.

Text inserted as a replacement is not recursively rescanned by that same rule as
part of the same rule application.

After the last rule, bashlog does **not** restart at the first rule and repeatedly
transform until a fixed point is reached.

This bounded model exists so processing cost and meaning remain understandable.
Security against content reintroduced by later replacements is provided by final
verification rather than iterative rewriting.

## Final Redaction Verification

After the ordered transformation pass and before emission, bashlog rechecks the
**complete rendered candidate** against every active rule in the selected
context.

This includes fixed, glob, and ERE rules.

A candidate is eligible for emission only when none of the active rules matches
it at the final verification point.

If:

- any active rule still matches;
- a matcher cannot be evaluated safely;
- or final verification cannot otherwise establish that the candidate satisfies
  the selected policy;

bashlog MUST NOT emit the candidate.

The library does not attempt iterative repair after final verification fails.
The operation returns `70`.

This protects against cases in which a later rule's literal replacement
reintroduces content protected by an earlier rule.

## Redaction Failure Diagnostic

When a logging operation must suppress its candidate because redaction or final
verification cannot be completed safely, the only permitted diagnostic candidate
is:

```text
bashlog: message suppressed
```

The diagnostic contains no original message, pattern, replacement, or other
secret-bearing rule content.

When an active context is available, the diagnostic itself MUST be checked
against that context's active rules before emission.  If the diagnostic matches a
rule or cannot be verified safely, bashlog emits no diagnostic and returns the
appropriate non-zero status.

When the failure is that an explicitly requested context is unavailable, bashlog
has no active rule set against which to verify the diagnostic.  It MAY emit the
same fixed diagnostic and return `69`.

A diagnostic is never permission to emit the original candidate.

## `bashlog_redaction_context_destroy`

### Synopsis

```text
bashlog_redaction_context_destroy CONTEXT
```

### Behavior

Destroys an active context as a bashlog policy object.

After success:

- the context cannot be used for logging;
- no new rules can be appended to that context name;
- the name cannot be reused during the current Bash process;
- bashlog removes its active references to the rule data as far as the
  implementation can intentionally control;
- non-secret tombstone state MAY remain so name reuse can be rejected.

The operation applies to the entire context.  There is no public individual-rule
deletion operation.

### Security Limitation

Context destruction is **not** secure memory erasure.

bashlog cannot prove that Bash, libc, the operating system, a core dump, or
historical copies no longer contain the prior string bytes.  Documentation and
function comments MUST NOT describe destruction as zeroization or cryptographic
destruction.

### Return Status

- `0`: active context destroyed.
- `64`: invalid argument count or invalid context identifier.
- `69`: context is unknown or already destroyed.

The function produces no standard output on success.

## `bashlog_redact`

### Synopsis

```text
bashlog_redact CONTEXT STRING
```

### Purpose

Transforms one Bash string under an active redaction context without adding a
severity label and without performing logging emission.

This function exists for caller-owned composition, including cases where a caller
wants explicitly redacted text before handing it to a sink outside bashlog.

### Behavior

On success:

1. validates and resolves the requested active context;
2. applies every rule once in registration order;
3. performs final verification against every active rule;
4. writes the verified redacted value to standard output with **no automatically
   added newline**.

The lack of an added newline makes the function suitable for command substitution
without introducing an extra record-formatting decision.

Example:

```bash
safe_value="$(bashlog_redact auth "${candidate}")" || exit
```

On any failure, the original `STRING` MUST NOT be written to standard output.

A fixed failure diagnostic MAY be written to standard error under the same safe
diagnostic rules used by logging calls.

### Return Status

- `0`: redacted and verified value written to standard output.
- `64`: invalid argument count or invalid context identifier.
- `69`: requested context is unknown or destroyed.
- `70`: transformation or final verification could not be completed safely.

### Non-Promise

`bashlog_redact` makes the returned string safe only with respect to the selected
context's active matcher rules at the point of final verification.  It does not
claim that the string is generally non-sensitive, safe for every audience, safe
for every downstream parser, or protected from later caller transformations.

If the caller modifies the returned string or combines it with additional data,
that later result has not been verified by bashlog unless it is passed through a
redaction boundary again.

## Severity Helpers

Each severity helper is semantically equivalent to `bashlog_log` with its level
fixed to the corresponding canonical severity.

For example:

```text
bashlog_info [--context CONTEXT] [--] FORMAT [ARGUMENT ...]
```

is equivalent in logging behavior to:

```text
bashlog_log info [--context CONTEXT] [--] FORMAT [ARGUMENT ...]
```

The helpers MUST NOT implement alternate rendering, redaction, verification, or
emission paths.

## No `bashlog_die` in the Initial Public Contract

The initial stable public API does not include `bashlog_die`.

Exiting a sourced application's shell is control-flow policy.  bashlog provides
logging primitives; the caller chooses whether and how to exit.

A caller may define:

```bash
die() {
  local status=1

  if [[ ${1:-} =~ ^[0-9]+$ ]]; then
    status="$1"
    shift
  fi

  bashlog_error "$@" || :
  exit "${status}"
}
```

The example is application code, not library-owned exit behavior.

A future namespaced exit helper would require explicit review because `exit` from
a sourced library function terminates the caller's shell process.

## No Automatic Timestamp or Environment Acquisition

The initial API does not automatically acquire timestamps, hostnames, Git
revisions, usernames, application names, or other environment-specific metadata.

Callers may provide such values explicitly:

```bash
bashlog_info 'started_at=%s' "$(date -Is)"
```

In that example, the caller invokes `date`; bashlog does not.  Command
substitution occurs before bashlog receives the argument, so the caller owns the
external-command behavior and any failure or disclosure associated with it.

## No Built-In External Sink

The initial API does not invoke `logger`, `tee`, network clients, or other helper
commands.

A caller may compose an external integration deliberately:

```bash
safe="$(bashlog_redact auth "${message}")" || exit
logger -- "${safe}"
```

The `logger` invocation is caller-owned.  Any metadata, buffering, transport,
security, or failure semantics introduced after `bashlog_redact` are outside the
bashlog sink contract.

## Security Promises

Subject to the governing ADRs and the exact matcher semantics above, the proposed
initial public contract promises:

1. A rule that has been accepted into a context is a security obligation for
   bashlog operations that explicitly select that context.
2. The complete rendered logging candidate is redacted and finally verified
   before standard-error emission.
3. A redaction or verification failure never falls back to emitting the original
   candidate.
4. Successful final verification means the candidate matches none of the active
   rules in the selected context at that point.
5. Fixed replacements are exact and literal; replacement text is never evaluated
   or interpreted as a secondary language.
6. No public getter, list, serialization, or inspection API returns secret-bearing
   rule contents.
7. Runtime redaction does not invoke external helper commands.
8. bashlog does not intentionally persist or export registered redaction state.
9. Exact representable multibyte values are supported by the fixed matcher.
10. All severity helpers converge through the same final redaction and emission
    boundary.

## Explicit Non-Promises

The proposed public contract does **not** promise:

1. automatic identification of passwords, tokens, PII, or other sensitive data;
2. secure memory, memory locking, or reliable zeroization;
3. protection from malicious code executing in the same Bash interpreter;
4. protection from `ptrace`, root, debuggers, core dumps, kernel compromise, or
   equivalent privileged memory access;
5. protection from caller-side `set -x` exposure before bashlog receives function
   arguments;
6. protection for data the caller writes through another path;
7. retroactive protection for data emitted before a rule was registered;
8. Unicode normalization or semantic equivalence for distinct byte sequences;
9. locale-independent glob or ERE semantics;
10. embedded-NUL support;
11. single-line normalization or generic log-injection prevention for caller
    message data;
12. secret management, encryption, credential storage, or vault functionality;
13. safety of downstream transformations performed after successful
    `bashlog_redact` output;
14. built-in syslog, network logging, file sinks, timestamps, hostnames, colors,
    tags, or application metadata in the initial contract.

## Shell Tracing Boundary

Callers must understand that:

```bash
set -x
bashlog_redaction_add auth fixed "${password}" '[REDACTED]'
```

may cause Bash itself to trace the expanded password **before** the function can
protect it.

bashlog cannot undo disclosure that already occurred at the caller's trace
boundary.

Security-sensitive applications SHOULD disable xtrace around secret-bearing
function calls or otherwise ensure the caller's tracing policy is appropriate.

## Context Destruction Boundary

Destroying a context means bashlog stops intentionally retaining and using that
active policy through its own data structures.

It does not mean the bytes have been securely removed from process memory.

This distinction is part of the public contract, not a documentation caveat to be
hidden in implementation notes.

## Caller-Owned Convenience Wrappers

bashlog intentionally leaves generic names to applications.

A caller may define:

```bash
debug() {
  bashlog_debug "$@"
}

info() {
  bashlog_info "$@"
}

warn() {
  bashlog_warning "$@"
}

error() {
  bashlog_error "$@"
}
```

Wrappers should call documented `bashlog_*` public functions and should not depend
on `__bashlog_*` implementation helpers.

bashlog does not require aliases, `expand_aliases`, `eval`, generated functions,
or `export -f` for this purpose.

## Initial Examples

### Ordinary Logging

```bash
bashlog_info 'application started'
bashlog_warning 'configuration file %s is deprecated' "${config_file}"
```

Expected standard-error records:

```text
info: application started
warning: configuration file /path/to/config is deprecated
```

### Set the Threshold

```bash
bashlog_level_set warning
bashlog_info 'not emitted'
bashlog_error 'emitted'
```

The info call returns `0` but writes nothing because it is below the configured
verbosity threshold.

### Register and Use a Fixed Secret

```bash
password='correct horse battery staple'

bashlog_redaction_add auth fixed \
  "${password}" \
  '[REDACTED PASSWORD]'

bashlog_info --context auth \
  'authentication failed for password=%s' \
  "${password}"
```

Expected standard-error record:

```text
info: authentication failed for password=[REDACTED PASSWORD]
```

### Literal Replacement Characters

```bash
bashlog_redaction_add auth fixed 'secret' '&-${USER}-\1-$(id)'
bashlog_info --context auth '%s' 'value=secret'
```

The replacement is literal.  No user-name expansion, command substitution,
backreference, or matched-text substitution occurs.

Expected record:

```text
info: value=&-${USER}-\1-$(id)
```

### Redact for a Caller-Owned Sink

```bash
safe_message="$(bashlog_redact auth "${message}")" || exit
some_caller_owned_sink "${safe_message}"
```

bashlog's promise ends at the verified value returned by `bashlog_redact`.
Behavior introduced by `some_caller_owned_sink` belongs to the caller.

## Features Deliberately Outside the Initial Contract

The following are intentionally deferred until the core contract has been
implemented, tested, and shown to need them:

- color output;
- timestamps generated by bashlog;
- application tags;
- hostnames;
- process identifiers;
- syslog facilities;
- built-in `logger` integration;
- file sinks;
- caller-selected file descriptors;
- network sinks;
- automatic environment or Git metadata;
- aliases for canonical severity names;
- generic short functions installed by the library;
- a namespaced `bashlog_die` control-flow helper;
- context rule listing;
- individual rule deletion or mutation;
- context name reuse after destruction;
- Unicode normalization;
- capture-based or expression-based replacement;
- extglob redaction syntax;
- automatic secret/PII discovery.

Deferral is intentional.  A future feature must preserve the security boundary
rather than expanding the public surface merely because an implementation is
possible.

## Required Test Implications

Before this specification can move from Draft to a stable implemented contract,
tests SHOULD demonstrate at minimum:

- source-time silence and absence of trap/shell-option/shopt mutation;
- Bash 4.3 representative behavior;
- threshold boundaries for every severity;
- exact standard-error rendering for every severity helper;
- logging functions do not write routine logs to standard output;
- invalid call syntax returns the documented status and does not emit caller data;
- unknown and destroyed requested contexts fail closed;
- context creation is atomic with first successful registration;
- active context policy is append-only;
- duplicate rules are rejected;
- empty patterns are rejected and empty replacements are accepted;
- replacement strings containing `&`, backslashes, `$()`, `${...}`, glob
  metacharacters, and ERE-like text remain literal;
- fixed matching handles multiple and adjacent occurrences;
- fixed matching handles representative UTF-8 values including accented Latin,
  Cyrillic, CJK, emoji, and combining sequences as exact input sequences;
- normalization-equivalent but byte-distinct strings are not falsely promised to
  match;
- glob and ERE zero-length-capable patterns are rejected;
- invalid ERE registration does not create or mutate context state;
- extglob semantics do not depend on ambient `shopt` state;
- rule ordering is deterministic;
- later replacements cannot reintroduce earlier protected content and still be
  emitted;
- final verification covers the complete rendered record, including the severity
  label and message;
- every successful redacted emission contains none of the active rule matches;
- redaction failure diagnostics contain no caller message or rule contents;
- a diagnostic matching an active rule is itself suppressed;
- `bashlog_redact` adds no newline and never writes the original string on
  failure;
- context destruction prevents future use and name reuse without claiming secure
  erasure;
- no runtime path invokes external commands;
- development, ordinary, and minified release artifacts exhibit equivalent
  behavior.

Security tests SHOULD include explicit negative assertions against stdout,
stderr, and captured diagnostics so a test cannot pass merely because the
expected replacement appeared while the original secret also leaked elsewhere.

## Governing Decisions

This draft specification is derived primarily from:

- ADR-002: Bash Runtime and Portability Baseline
- ADR-007: Doxygen-Based Verbose Source Documentation Standard
- ADR-009: Observable Behavior Testing Across Shipped Artifacts
- ADR-013: Sourceable Library Scope and Responsibility Boundary
- ADR-014: Pure Bash Runtime and External Command Boundary
- ADR-015: Namespaced Public API and Caller-Owned Convenience Wrappers
- ADR-016: Modular Source Assembly for a Sourceable Library
- ADR-017: Logging Pipeline, Levels, Formatting, and Emission
- ADR-018: Redaction as an Opt-In Security Boundary
- ADR-019: Readability, Auditability, and Rejection of Obscurity
- ADR-020: Redaction Context Lifecycle and State Model
- ADR-021: Redaction Rule Registration, Ordering, and Replacement Semantics
- ADR-022: Fixed-String Redaction and Multibyte Guarantees
- ADR-023: Glob and ERE Redaction Semantics
- ADR-024: Final Redaction Verification and Fail-Closed Output Boundary

If implementation experience demonstrates that this specification cannot satisfy
a governing architectural promise clearly and readably on Bash 4.3, the project
should revisit the relevant ADR rather than quietly weakening the documented
contract.
