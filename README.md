# bashlog

bashlog is a sourceable pure-Bash logging library designed around explicit,
fail-closed redaction of caller-registered sensitive values and patterns.

The project is currently in **pre-implementation development**.  Its architecture
and normative public contract are accepted; runtime implementation, activated
contract tests, and the first stable release remain to be completed.  The
promises below therefore describe the accepted contract the implementation must
satisfy and must not be mistaken for already-shipped runtime behavior until
implementation and tests demonstrate conformance.

The accepted design targets Bash 4.3 or newer and deliberately favors explicit,
inspectable behavior over cleverness, implicit shell state, or broad claims that
the Bash runtime cannot support.

## What the Accepted Contract Promises

Once implemented in conformance with the accepted architecture, bashlog makes the
following concrete promises.

- **Sourcing is non-invasive.**  Loading bashlog does not install traps, change
  `set` or `shopt` options, define generic logging functions, emit output, access
  the network, or take ownership of application control flow.
- **Runtime operation is pure Bash.**  Logging, formatting, redaction,
  verification, and emission do not invoke external commands.
- **Redaction is explicit.**  bashlog does not guess which data is sensitive.
  The caller registers values or patterns that require protection and explicitly
  selects the corresponding context for a logging operation.
- **Accepted rules become security obligations.**  When a logging call selects an
  active context, bashlog treats its accepted rules as requirements rather than
  best-effort presentation preferences.
- **Redaction failure fails closed.**  If required redaction or final verification
  cannot be completed safely, bashlog does not emit the original candidate.
- **Every built-in logging path crosses the same final boundary.**  Debug,
  informational, warning, error, and other severity helpers do not receive a
  less-protected output path.
- **Replacement text is always literal.**  Replacement values are not evaluated
  as shell code, parameter expansion, command substitution, regular-expression
  backreferences, `&` matched-text substitution, glob expansion, or another
  expression language.
- **Fixed matching protects exact representable multibyte values.**  Exact UTF-8
  byte sequences may be registered as fixed secrets without turning their
  characters into pattern syntax.
- **Final verification checks the complete rendered candidate.**  A successfully
  emitted redacted record matches none of the selected context's active fixed,
  glob, or ERE rules at the final verification point.
- **Registered secret-bearing rule contents are not exposed by a public retrieval
  API.**  bashlog does not intentionally serialize, persist, export, or pass its
  runtime redaction state to external helper commands.
- **The security-critical path remains readable.**  bashlog rejects obscurity,
  reversible encoding, `eval`, generated-code tricks, and fake encapsulation as
  substitutes for an actual security boundary.

These promises are intentionally specific.  The project prefers claims that can
be inspected and tested over statements such as "bashlog securely handles
secrets."

## What bashlog Does Not Promise

The limits are part of the contract, not fine print.

bashlog does **not** promise:

- automatic discovery of passwords, tokens, PII, or other sensitive data;
- permission to send sensitive information to logging code unnecessarily;
- secure memory, memory locking, or reliable zeroization;
- protection from malicious code already executing in the same Bash process;
- protection from debuggers, `ptrace`, root, kernel compromise, core dumps, or
  equivalent privileged memory inspection;
- protection from caller-side `set -x` tracing that exposes expanded arguments
  before bashlog receives them;
- protection for a secret already written through another logging or output path;
- Unicode normalization or semantic equivalence between distinct byte sequences;
- locale-independent glob or ERE semantics;
- embedded-NUL support, because Bash variables cannot faithfully represent such
  data;
- general secret-management, encryption, credential-vault, or secure-enclave
  functionality;
- safety of arbitrary downstream transformations performed after bashlog returns
  a verified redacted string.

A particularly important boundary is same-process state: Bash does not provide
private memory between sourced functions.  bashlog can avoid intentionally
exposing registered values through its supported interface, diagnostics,
persistence, environment export, and subprocess invocation, but it cannot make a
plaintext value inaccessible to hostile code running in the same interpreter.

The project will not obscure internal variables and call that privacy.

## Trust Model

bashlog is intended to earn trust through reviewable behavior, not by asking
consumers to accept a generic security assertion.

The design makes the following evidence available:

- verbose architectural decisions with explicit promises, non-promises, rejected
  alternatives, and failure models;
- an accepted normative public behavior specification;
- exact `bash-doxygen`-compatible source documentation beside implementation;
- a security-critical path written as direct Bash rather than generated or
  obscured code;
- negative tests that look for forbidden original secrets as well as expected
  replacements;
- tests against every shipped artifact representation;
- explicit documentation of conditions the runtime cannot defend against.

See [`doc/decisions.md`](doc/decisions.md) for the concise decision map and
[`doc/adr/`](doc/adr/) for the complete architectural reasoning.

## Accepted Initial API

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

The full accepted contract, including arguments, return statuses, severity
thresholds, stream behavior, matcher semantics, and failure diagnostics, is in
[`doc/bashlog-spec.md`](doc/bashlog-spec.md).

That specification is normative for implementation.  The current
starter-derived runtime does not yet implement the API, so specification
acceptance must not be represented as runtime conformance.

## Basic Logging

The accepted logging interface uses conventional `printf`-style construction:

```bash
bashlog_info 'application started'
bashlog_warning 'configuration file %s is deprecated' "${config_file}"
bashlog_error 'request %s failed with status %s' "${request_id}" "${status}"
```

All routine log records are written to standard error.  Standard output remains
available to the application for data, pipelines, and command substitution.

The initial rendered form is deliberately minimal:

```text
info: application started
warning: configuration file /path/to/config is deprecated
error: request 42 failed with status 500
```

The initial contract does not automatically add timestamps, hostnames, process
IDs, application names, colors, tags, Git metadata, or syslog facilities.

Callers remain free to prepare such data themselves.  If a caller invokes an
external command to obtain a value, that invocation belongs to the caller rather
than bashlog:

```bash
bashlog_info 'started_at=%s' "$(date -Is)"
```

The `date` command runs before bashlog receives the argument.  bashlog itself did
not invoke an external command.

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

The accepted default threshold is `info`.  A message is eligible for output when
its severity number is less than or equal to the active threshold.

```bash
bashlog_level_set warning

bashlog_info 'suppressed by threshold'
bashlog_error 'emitted'
```

Threshold suppression is a successful logging-policy decision and returns zero.

The namespaced initial API uses the full canonical severity names.  It does not
claim generic names such as `warn`, `error`, or `die` for the caller.

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

This keeps generic names under application control while letting the stable
library surface remain namespaced and collision-resistant.

bashlog does not require aliases, `expand_aliases`, `eval`, generated wrappers, or
`export -f` to provide this convenience.

The initial contract intentionally does not include `bashlog_die`.  Exiting a
sourced application's shell is application control-flow policy.  A caller may log
and then choose its own exit behavior.

## Redaction Contexts

Redaction is organized into named contexts.

A context has the accepted lifecycle:

```text
unseen -> active -> destroyed
```

There is no separate empty-context creation call.  The first successfully
registered rule creates the context atomically.

Context names use the restricted identifier form:

```text
[A-Za-z_][A-Za-z0-9_.:-]*
```

Active contexts are append-only.  Rules may be added as new protected values
become known, including after the context has already been used.  Existing rules
cannot be edited, reordered, or individually removed through the public API.

Destroying a context makes the context unavailable and prevents reuse of the same
name for the remainder of that Bash process.  Destruction removes bashlog's
active references as far as the implementation can intentionally control; it is
**not** secure memory erasure.

## Registering Redaction Rules

The accepted registration interface is:

```text
bashlog_redaction_add CONTEXT MATCHER PATTERN REPLACEMENT
```

The matcher is always explicit and is exactly one of:

```text
fixed
glob
ere
```

For a known password or token, `fixed` is the preferred matcher:

```bash
password='correct horse battery staple'

bashlog_redaction_add auth fixed \
  "${password}" \
  '[REDACTED PASSWORD]'
```

The context `auth` becomes active when that first rule is accepted.

Rules preserve successful registration order.  Duplicate matcher/pattern pairs
are rejected instead of silently changing an existing rule.

Empty patterns are rejected.  Empty replacements are valid and remove matches.

## Literal Replacement Means Literal

Replacement strings are data, not code.

For example:

```bash
bashlog_redaction_add auth fixed \
  'secret' \
  '&-${USER}-\1-$(id)'
```

The intended replacement is exactly:

```text
&-${USER}-\1-$(id)
```

There is no `&` matched-text substitution, `${USER}` expansion, `\1`
backreference, or `$(id)` command substitution performed by bashlog.

This invariant applies to fixed, glob, and ERE matchers alike.

## Logging With Redaction

A logging call explicitly selects a context:

```bash
bashlog_info --context auth \
  'authentication failed for password=%s' \
  "${password}"
```

The accepted visible result is:

```text
info: authentication failed for password=[REDACTED PASSWORD]
```

A call that omits `--context` performs no context-based redaction.  bashlog does
not maintain an implicit ambient current context in the initial API.

That distinction is important:

- **no context requested** means the caller intentionally chose no context-based
  redaction for the operation;
- **a requested context is unknown or destroyed** means the caller attempted to
  rely on a policy bashlog cannot provide, so the operation fails closed.

An unavailable requested context is never silently treated as an empty rule set.

## Matcher Behavior

### `fixed`

Every character is literal.  Exact non-overlapping occurrences are replaced.
Glob and ERE metacharacters have no special meaning.

Exact representable multibyte sequences are protected as exact strings.  bashlog
does not promise Unicode normalization or case-fold equivalence.

### `glob`

`glob` uses a limited basic Bash glob language, including ordinary `*`, `?`, and
bracket expressions.  Extended-glob operator syntax is rejected so rule meaning
does not depend on whether the caller happened to enable `extglob`.

Glob patterns capable of matching empty input are rejected.

### `ere`

`ere` uses Bash `[[ STRING =~ ERE ]]` semantics.  Invalid EREs and EREs capable of
matching empty input are rejected during registration.

Capture groups may affect matching, but replacement strings never gain capture
backreference semantics.

Glob and ERE behavior follows the caller's existing locale where Bash itself is
locale-sensitive.  bashlog does not modify locale state.

## Fail-Closed Final Verification

Rules are applied once each, in registration order, using bounded non-overlapping
passes.  bashlog does not repeatedly execute the rule set until a fixed point is
reached.

After transformation, the **complete rendered candidate** is checked against
every active fixed, glob, and ERE rule in the selected context immediately before
emission.

A candidate is emitted only if none of those rules still matches.

If a match remains or verification cannot be completed safely, the candidate is
suppressed rather than repaired iteratively or emitted unchanged.

This is intended to prevent interactions such as a later replacement
reintroducing a value protected by an earlier rule.

The central invariant is:

> A successfully emitted redacted candidate matches none of the selected
> context's active rules at the final verification point.

## Redaction Failure Diagnostics

A redaction failure does not echo the original message, failed candidate,
pattern, replacement, or secret-bearing rule state merely to explain what went
wrong.

The accepted fixed diagnostic candidate is:

```text
bashlog: message suppressed
```

When an active context exists, even that diagnostic must satisfy the context's
final rule checks before it may be emitted.  If the diagnostic itself cannot be
verified safely, bashlog prefers silence.

Logging availability is deliberately subordinate to the explicit redaction
obligation.

## Transform Without Logging

For caller-owned integrations, the accepted API includes:

```text
bashlog_redact CONTEXT STRING
```

On success, the function writes the verified redacted string to standard output
without automatically adding a newline.

```bash
safe_message="$(bashlog_redact auth "${message}")" || exit
```

A caller may then deliberately pass that value elsewhere.

The bashlog guarantee applies to the returned value at the verification point.
If the caller modifies it, appends new data, or sends it through an external sink
with additional behavior, those later operations belong to the caller.

## Shell Tracing Warning

Caller-side tracing can expose secrets before bashlog receives them.

For example:

```bash
set -x
bashlog_redaction_add auth fixed "${password}" '[REDACTED]'
```

may cause Bash itself to print the expanded password as part of xtrace output.
No function can retroactively redact text Bash already emitted before entering
the function.

Security-sensitive callers should ensure their tracing policy is appropriate
around secret-bearing arguments.

## Planned Build and Consumption Model

The current repository still contains implementation scaffolding inherited from
`template-bash`; the bashlog-specific runtime and final artifact naming have not
yet been implemented.  The intended first-release build will produce three
standalone representations named:

```text
dist/bashlog.dev.bash
dist/bashlog.dev.bash.sha256
dist/bashlog.bash
dist/bashlog.bash.sha256
dist/bashlog.min.bash
dist/bashlog.min.bash.sha256
```

The planned artifact roles are:

- `bashlog.dev.bash`: retain maintained Doxygen comments;
- `bashlog.bash`: remove full-line source comments while preserving behavior;
- `bashlog.min.bash`: provide the minified consumer representation.

All three sourceable artifacts are intended to satisfy the same behavior
contract.  The `.sha256` companions will use conventional SHA-256 checksum-file
syntax.

The expected consumption model is a pinned standalone artifact, commonly
materialized into a repository by [bashdeps](https://github.com/wesley-dean/bashdeps)
and then sourced by the consuming script.

Conceptually:

```text
bashlog release
    -> pinned URL + reviewed SHA-256 digest
    -> bashdeps
    -> repository-local bashlog.bash
    -> source from consumer
```

bashlog itself will have no runtime dependency on bashdeps or on a particular
vendor-directory layout.  bashdeps is an acquisition mechanism used before
runtime, not a component of the logging library.

## Documentation Model

bashlog deliberately treats documentation as part of the architecture.

The hierarchy is:

- `README.md`: public orientation, major promises, major non-promises, and usage;
- `doc/decisions.md`: concise one-to-three-sentence architectural decision map;
- `doc/adr/*.md`: full context, reasoning, promises, non-promises, adversary and
  failure models, rejected alternatives, consequences, and follow-ups;
- `doc/bashlog-spec.md`: accepted normative public behavior;
- Doxygen comments: implementation-level contracts beside maintained Bash source;
- Bats tests: executable evidence for observable guarantees and invariants.

Maintained Bash source uses the exact `bash-doxygen`-compatible documentation
model defined in [`doc/documentation-standard.md`](doc/documentation-standard.md).
Doxygen lines begin with `##`, use structural commands such as `@file`, `@fn`,
`@var`, and `@param`, and preserve detailed contracts, assumptions, output,
return statuses, examples, and failure semantics near the code they govern.

This syntax is a project requirement, not loose inspiration for a similar comment
style.

## Testing Direction

The project follows documentation-driven, test-second development for
consequential behavior:

1. establish or identify governing ADRs;
2. define the public contract and Doxygen interface documentation;
3. write focused behavior and negative security tests;
4. implement the smallest coherent code that satisfies those contracts;
5. validate every artifact representation;
6. compare the completed behavior back against the governing decisions.

Security tests must look for what must **not** happen.  A test does not prove
redaction merely because `[REDACTED]` appears; it should also verify that the
original protected value appears nowhere in stdout, stderr, diagnostics, or other
captured output for the behavior under test.

## Build Lifecycle

GNU Make is the canonical development and CI orchestration surface.  The current
starter-derived Makefile already provides the project-family lifecycle, although
bashlog-specific source assembly and artifact naming still need to replace the
starter behavior during implementation:

- `make deps` synchronizes repository dependencies and may use the network.
- `make deps-check` verifies prepared dependency state offline.
- `make build` creates the currently configured generated artifacts without
  dependency synchronization.
- `make all` runs dependency convergence and then builds.
- `make check` performs maintained-source validation.
- `make format` uses the project shfmt policy.
- `make test` exercises every currently configured generated artifact flavor.
- `make test-report` writes JUnit reports under `test-results/`.
- `make docs` generates Doxygen reference output under `doc/reference/` using the
  prepared bash-doxygen filter.

Generated Doxygen reference output is ephemeral and is not committed.

## Architectural Decisions

The complete ADR index is in [`doc/adr/README.md`](doc/adr/README.md).

The concise current decision map is in
[`doc/decisions.md`](doc/decisions.md).

The most directly relevant bashlog design records are ADR-013 through ADR-024,
covering sourceable-library scope, runtime purity, API namespacing, modular source
assembly, the logging pipeline, redaction trust boundaries, auditability, context
lifecycle, matcher semantics, and fail-closed final verification.

Those bashlog-specific ADRs are **Accepted** and govern implementation.  Their
acceptance records the chosen architecture; the current starter-derived runtime
still must be replaced and demonstrated against the accepted contract tests.

## License and Contributions

This project is dedicated to the public domain under CC0 1.0 Universal.  See
`LICENSE` and `CONTRIBUTING.md` for details, and `CODE_OF_CONDUCT.md` for project
collaboration expectations.
