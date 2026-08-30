# bashlog

bashlog is a sourceable pure-Bash logging library designed around explicit,
fail-closed redaction of caller-registered sensitive values and patterns.

The project is currently **pre-release**, but the initial Accepted architecture,
public API, runtime implementation, Doxygen contracts, and behavior/security test
suite are now present in the repository.  The implementation targets Bash 4.3 or
newer and deliberately favors explicit, inspectable behavior over cleverness,
implicit shell state, or security claims the Bash runtime cannot support.

## What bashlog Promises

bashlog makes deliberately narrow, testable promises.

- **Sourcing is non-invasive.**  Loading bashlog does not install traps, change
  `set` options, leave `shopt` options changed, define generic logging functions,
  emit output, access the network, or take ownership of application control flow.
- **Runtime operation is pure Bash.**  Logging, formatting, redaction,
  verification, and emission use Bash language facilities and builtins rather
  than invoking external commands.
- **Redaction is explicit.**  bashlog does not guess which data is sensitive.
  Callers register values or patterns and explicitly select the corresponding
  context for logging operations that require protection.
- **Accepted rules are security obligations.**  When a logging call selects an
  active context, its accepted rules are requirements rather than best-effort
  presentation preferences.
- **Redaction fails closed.**  If required transformation or final verification
  cannot be completed safely, bashlog does not emit the original candidate.
- **Every built-in severity uses the same protected path.**  Debug,
  informational, warning, error, and more severe helpers do not gain alternate
  unredacted sinks.
- **Replacement text is always literal.**  Replacement values are never
  interpreted as shell code, parameter expansion, command substitution, ERE
  backreferences, `&` matched-text substitution, glob expansion, or another
  secondary expression language.
- **Fixed matching protects exact representable multibyte values.**  Exact
  multibyte Bash strings can be registered without turning their characters into
  pattern syntax.
- **Final verification covers the complete rendered candidate.**  A successfully
  emitted redacted record matches none of the selected context's active fixed,
  glob, or ERE rules at the final verification point.
- **Registered secret-bearing rule contents are not exposed by a public retrieval
  API.**  bashlog does not intentionally serialize, persist, export, or hand its
  runtime redaction state to helper processes.
- **The security-critical path remains readable.**  bashlog rejects obscurity,
  reversible encoding, `eval`, generated-code tricks, and fake encapsulation as
  substitutes for an actual boundary.

These claims are intentionally behavioral.  The project prefers evidence that a
consumer can inspect and test over broad statements such as "bashlog securely
handles secrets."

## What bashlog Does Not Promise

The limits are part of the contract, not fine print.

bashlog does **not** promise:

- automatic discovery of passwords, tokens, PII, or other sensitive data;
- permission to send sensitive information to logging code unnecessarily;
- secure memory, memory locking, or reliable zeroization;
- protection from malicious code already executing in the same Bash interpreter;
- protection from debuggers, `ptrace`, root, kernel compromise, core dumps, or
  equivalent privileged memory inspection;
- protection from caller-side `set -x` tracing that exposes expanded arguments
  before bashlog receives them;
- protection for a secret already written through another output path;
- Unicode normalization or semantic equivalence between distinct string
  representations;
- locale-independent glob or ERE semantics;
- embedded-NUL support, because ordinary Bash variables cannot faithfully carry
  such data;
- general secret-management, encryption, credential-vault, or secure-enclave
  functionality;
- safety of arbitrary downstream transformations after `bashlog_redact` returns
  a verified value.

A particularly important boundary is same-process state.  Bash does not provide
private memory between sourced functions.  bashlog can avoid intentionally
exposing registered values through its supported interface, diagnostics,
persistence, environment export, and subprocess invocation, but it cannot make a
plaintext value inaccessible to hostile code running in the same interpreter.

The project will not obscure internal variables and call that privacy.

## Runtime Requirements

- Bash 4.3 or newer.
- No external runtime commands are required by bashlog itself.

External development tools are used to build, test, document, and release the
project.  That build-time tooling is outside the consumer runtime boundary.

## Public API

The initial public API is intentionally small:

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

The normative details, including argument grammar, return statuses, threshold
behavior, matcher semantics, streams, and failure handling, are in
[`doc/bashlog-spec.md`](doc/bashlog-spec.md).

Functions named `__bashlog_*` are implementation details.  Their names are
intentionally readable, but they do not participate in the stable public API.

## Basic Logging

The logging interface uses Bash builtin `printf`-style message construction:

```bash
bashlog_info 'application started'
bashlog_warning 'configuration file %s is deprecated' "${config_file}"
bashlog_error 'request %s failed with status %s' "${request_id}" "${status}"
```

Routine log records are written to standard error so standard output remains
available for application data, pipelines, and command substitution.

The initial rendered form is deliberately minimal:

```text
info: application started
warning: configuration file /path/to/config is deprecated
error: request 42 failed with status 500
```

bashlog appends one newline to a log record.  It does not automatically add
timestamps, hostnames, process IDs, application names, colors, tags, Git metadata,
or syslog facilities.

Callers remain free to prepare such data themselves.  If caller code invokes an
external command to obtain a value, that command belongs to the caller rather than
bashlog:

```bash
bashlog_info 'started_at=%s' "$(date -Is)"
```

The `date` process runs during caller-side argument construction before bashlog
receives the resulting string.

When arbitrary caller-controlled text should be logged literally, use a literal
format and pass the text as data:

```bash
bashlog_info '%s' "${untrusted_text}"
```

A caller-controlled format string receives Bash `printf` semantics.

## Log Levels

bashlog uses the conventional eight syslog severity levels:

| Number | Name | Helper |
| ---: | --- | --- |
| 0 | `emergency` | `bashlog_emergency` |
| 1 | `alert` | `bashlog_alert` |
| 2 | `critical` | `bashlog_critical` |
| 3 | `error` | `bashlog_error` |
| 4 | `warning` | `bashlog_warning` |
| 5 | `notice` | `bashlog_notice` |
| 6 | `info` | `bashlog_info` |
| 7 | `debug` | `bashlog_debug` |

The default threshold is `info`.  A message is eligible for emission when its
severity number is less than or equal to the active threshold.

```bash
bashlog_level_set warning

bashlog_info 'suppressed by threshold'
bashlog_error 'emitted'
```

Threshold suppression is a successful logging-policy decision and returns zero.

The active threshold can be queried on standard output:

```bash
level="$(bashlog_level_get)" || exit
printf 'level=%s\n' "${level}"
```

Canonical severity names are case-sensitive.  Short aliases such as `warn`,
`err`, and `crit` are not part of the namespaced public API.

## Caller-Owned Short Names

Applications that prefer shorter logging calls can define ordinary wrappers:

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

This keeps generic names under application control while the library surface
remains namespaced and collision-resistant.

bashlog does not require aliases, `expand_aliases`, `eval`, generated wrappers, or
`export -f` for this convenience.

The initial API intentionally does not include `bashlog_die`.  Exiting a sourced
application is application control-flow policy.

## Redaction Contexts

Redaction rules are grouped into named contexts with the lifecycle:

```text
unseen -> active -> destroyed
```

There is no separate empty-context creation call.  The first successfully
registered rule creates the context atomically.

Context names match:

```text
[A-Za-z_][A-Za-z0-9_.:-]*
```

Active contexts are append-only.  Additional rules may be registered as new
protected values become known, including after a context has already been used.
Existing rules cannot be edited, reordered, or individually removed through the
public API.

Destroying a context makes it unavailable and prevents reuse of the same name for
the remainder of the Bash process:

```bash
bashlog_redaction_context_destroy auth
```

Destruction removes bashlog's active references as far as the implementation can
intentionally control.  It is **not** secure memory erasure, zeroization, or proof
that Bash no longer contains historical copies of a value.

## Registering Redaction Rules

The registration interface is:

```text
bashlog_redaction_add CONTEXT MATCHER PATTERN REPLACEMENT
```

The matcher is explicit and exactly one of:

```text
fixed
glob
ere
```

For known passwords, tokens, API keys, and similar exact values, `fixed` is the
recommended matcher:

```bash
password='correct horse battery staple'

bashlog_redaction_add auth fixed \
  "${password}" \
  '[REDACTED PASSWORD]'
```

The `auth` context becomes active when that first rule is accepted.

Rules preserve successful registration order.  A duplicate `(matcher, pattern)`
pair is rejected rather than silently modifying an existing rule.

Empty patterns are rejected.  Empty replacements are valid and remove matching
text.

A rule whose replacement itself satisfies the same rule is rejected because it
could never satisfy final verification after performing a match.

## Literal Replacement Means Literal

Replacement strings are data, not code.

For example:

```bash
bashlog_redaction_add auth fixed \
  'secret' \
  '&-${USER}-\1-$(id)'
```

The replacement is exactly:

```text
&-${USER}-\1-$(id)
```

There is no `&` matched-text substitution, `${USER}` parameter expansion, `\1`
backreference, or `$(id)` command substitution performed by bashlog.

This invariant applies to fixed, glob, and ERE matchers.

## Logging With Redaction

A logging call explicitly selects one active context:

```bash
bashlog_info --context auth \
  'authentication failed for password=%s' \
  "${password}"
```

The resulting record is:

```text
info: authentication failed for password=[REDACTED PASSWORD]
```

A call that omits `--context` performs no context-based redaction.  There is no
implicit ambient redaction context.

That distinction is important:

- **no context requested** means the caller intentionally chose no context-based
  redaction for that call;
- **a requested context is invalid, unknown, or destroyed** means the caller tried
  to rely on a policy bashlog cannot provide, so the operation fails closed.

An unavailable requested context is never treated as an empty rule set.

## Matcher Behavior

### `fixed`

Every character is literal.  Exact non-overlapping occurrences are replaced from
left to right.  Glob and ERE metacharacters have no special meaning.

Exact representable multibyte strings are supported.  bashlog does not normalize
Unicode or perform case folding, canonical-equivalence matching, transliteration,
or transformation-aware secret discovery.

If the caller knows the exact sensitive value, prefer `fixed`.

### `glob`

`glob` uses a deliberately limited basic Bash pattern language, including `*`,
`?`, and bracket expressions.

Extended-glob operator syntax such as `@(…)`, `+(…)`, `*(…)`, `?(…)`, and `!(…)`
is rejected so rule meaning does not depend on ambient `extglob` state.

Glob patterns capable of matching empty input are rejected.  Substring selection
is leftmost start, then longest match at that start.

### `ere`

`ere` uses Bash `[[ STRING =~ ERE ]]` semantics.

Invalid EREs and expressions capable of matching empty input are rejected during
registration.  Capture groups may affect matching, but they never create
replacement backreference semantics.

bashlog locates ERE matches against the complete original rule input rather than
searching for the first literal copy of `BASH_REMATCH[0]`.  This distinction
preserves whole-input anchor behavior when an identical matched string appears at
another position.

For example, an ERE `foo$` applied to:

```text
foo middle foo
```

redacts the final `foo`, not the earlier identical substring.

### Locale and `nocasematch`

Glob and ERE matching follows the caller's current locale where Bash/libc defines
locale-sensitive behavior.  bashlog does not change the caller's locale.

Bash's `nocasematch` option would normally make `[[ == ]]` and `[[ =~ ]]`
case-insensitive.  bashlog's accepted matcher contract is case-sensitive, so the
implementation snapshots that option, disables it only around the individual
Bash-native match, and restores the caller's prior state before returning.

This behavior is covered by the contract suite.

## Fail-Closed Final Verification

Rules are applied once each, in successful registration order, using bounded
non-overlapping passes.  bashlog does not repeatedly execute the rule set until a
fixed point is reached.

After transformation, the **complete rendered candidate** is checked again
against every active fixed, glob, and ERE rule in the selected context immediately
before emission.

A candidate is eligible for emission only when none of those rules matches.

If a match remains or verification cannot be completed safely, the candidate is
suppressed rather than repaired iteratively or emitted unchanged.

This catches interactions such as a later replacement reintroducing a value
protected by an earlier rule.

The central invariant is:

> A successfully emitted redacted candidate matches none of the selected
> context's active rules at the final verification point.

## Redaction Failure Diagnostics

A redaction failure does not echo the original message, failed candidate, pattern,
replacement, or secret-bearing rule state merely to explain what went wrong.

The only diagnostic candidate is:

```text
bashlog: message suppressed
```

When an active context exists, even that fixed diagnostic must satisfy the
context's matcher policy before it may be emitted.  If it matches a rule or cannot
be verified safely, bashlog remains silent and returns the appropriate non-zero
status.

Logging availability is deliberately subordinate to an explicit redaction
obligation.

## Transform Without Logging

For caller-owned integrations, use:

```text
bashlog_redact CONTEXT STRING
```

On success, the function writes the verified transformed string to standard
output **without adding a newline**:

```bash
safe_message="$(bashlog_redact auth "${message}")" || exit
```

A caller may then deliberately pass the value elsewhere.

The bashlog guarantee applies to the returned value at the verification point. If
the caller modifies it, appends new data, or sends it through a downstream system
that changes it, those later operations belong to the caller.

## Return Statuses

The shared public status vocabulary is:

| Status | Meaning |
| ---: | --- |
| `0` | Operation succeeded; for logging, threshold suppression also counts as success. |
| `64` | Invalid API syntax, level, context identifier, option, or formatting input. |
| `65` | Invalid, duplicate, zero-length-capable, self-matching, or otherwise unacceptable redaction rule. |
| `69` | A specifically requested context is unknown, destroyed, or otherwise unavailable. |
| `70` | Redaction, final verification, or another security-sensitive transformation could not be completed safely. |
| `74` | Final logging emission to standard error failed. |

Individual functions use the applicable subset.  See the specification and
Doxygen blocks for exact per-function behavior.

## Shell Tracing Warning

Caller-side tracing can expose secrets before bashlog receives them.

For example:

```bash
set -x
bashlog_redaction_add auth fixed "${password}" '[REDACTED]'
```

may cause Bash itself to print the expanded password before entering the function.
No function can retroactively redact text already emitted by the caller's trace
boundary.

Security-sensitive callers should ensure their tracing policy is appropriate
around secret-bearing arguments.

## Build and Artifacts

GNU Make is the canonical orchestration surface.

Prepare repository dependencies and build:

```bash
make deps
make build
```

Or converge dependencies and build in one command:

```bash
make all
```

The build produces three standalone sourceable representations:

```text
dist/bashlog.dev.bash
dist/bashlog.dev.bash.sha256
dist/bashlog.bash
dist/bashlog.bash.sha256
dist/bashlog.min.bash
dist/bashlog.min.bash.sha256
```

Their roles are:

- `bashlog.dev.bash`: assembled source retaining the maintained Doxygen comments;
- `bashlog.bash`: ordinary readable artifact with full-line comments removed;
- `bashlog.min.bash`: minified consumer representation.

All three artifacts are required to satisfy the same public behavior contract.
They are also tested after repository dependency state is removed so consumer
runtime does not accidentally depend on `vendor/`.

`.sha256` companions use conventional SHA-256 checksum-file syntax.  Current
builds do not retain duplicate `.256` companions.

## Consumption With bashdeps

The expected project-family consumption model is a pinned standalone artifact,
commonly materialized by
[`wesley-dean/bashdeps`](https://github.com/wesley-dean/bashdeps) before runtime.

Conceptually:

```text
bashlog release
    -> pinned URL + reviewed SHA-256 digest
    -> bashdeps
    -> repository-local bashlog.bash
    -> source from consumer
```

bashlog itself has no runtime dependency on bashdeps or a particular vendor
layout.  bashdeps is an acquisition/verification mechanism used before runtime.

A consumer ultimately sources the verified artifact:

```bash
source "${project_root}/vendor/bashlog.bash"

bashlog_info 'application started'
```

## Testing

The active behavior/security suite is under `tests/contract/`.

`make test` executes the same suite against:

- `dist/bashlog.dev.bash`;
- `dist/bashlog.bash`;
- `dist/bashlog.min.bash`.

`make test-report` writes JUnit reports under `test-results/` for the same matrix.

The suite covers source-time behavior, levels, formatting, context lifecycle,
fixed/glob/ERE semantics, Unicode exact-string fixtures, anchored ERE behavior,
ambient `extglob`/`nocasematch` state, fail-closed rule interactions, safe
diagnostics, literal replacements, unavailable contexts, and the no-external-
runtime-command boundary.

Security tests assert absence as well as presence.  A test does not prove
redaction merely because a replacement marker appears; protected originals must
also be absent from all captured bashlog output.

CI additionally runs a representative compatibility contract against all three
artifacts under Bash 4.3.

## Documentation Model

bashlog deliberately treats documentation as part of the architecture.

The hierarchy is:

- `README.md`: public orientation, promises, non-promises, and representative
  usage;
- `doc/decisions.md`: concise architectural decision map;
- `doc/adr/*.md`: full context, reasoning, promises, non-promises, adversary and
  failure models, rejected alternatives, consequences, and follow-ups;
- `doc/bashlog-spec.md`: normative current public behavior;
- Doxygen comments: implementation-level contracts beside maintained Bash source;
- Bats tests: executable evidence for observable guarantees and invariants.

Maintained Bash source uses the exact `bash-doxygen`-compatible documentation
model defined in
[`doc/documentation-standard.md`](doc/documentation-standard.md).  Doxygen comment
lines begin with `##`, structural declarations use commands such as `@file`,
`@fn`, `@var`, and `@param`, and security-sensitive helpers preserve detailed
reasoning near the implementation they govern.

This syntax is a project requirement, not inspiration for a similar comment
style.

Generated Doxygen reference output lives under `doc/reference/` and is ephemeral.

## Architectural Decisions

The complete ADR index is in [`doc/adr/README.md`](doc/adr/README.md), and the
concise current decision map is in [`doc/decisions.md`](doc/decisions.md).

ADR-013 through ADR-024 govern the bashlog-specific architecture: sourceable
library scope, runtime purity, namespaced API, modular assembly, logging pipeline,
redaction trust boundary, auditability, context lifecycle, matcher semantics, and
fail-closed final verification.

Those decisions are **Accepted**.  Changes that conflict with them should revise
architecture explicitly rather than allowing implementation convenience to
silently redefine the contract.

## License and Contributions

This project is dedicated to the public domain under CC0 1.0 Universal.  See
`LICENSE` and `CONTRIBUTING.md` for details, and `CODE_OF_CONDUCT.md` for project
collaboration expectations.
