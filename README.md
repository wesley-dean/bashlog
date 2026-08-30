# bashlog

bashlog is a sourceable pure-Bash logging library designed around predictable
logging, explicit developer-owned redaction, and a small auditable runtime.

The project is currently **pre-release**.  It targets Bash 4.3 or newer and
favors explicit, inspectable behavior over cleverness, implicit shell state, or
security claims the Bash runtime cannot support.

## What bashlog Promises

bashlog makes deliberately narrow, testable promises.

- **Sourcing is non-invasive.**  Loading bashlog does not install traps, change
  `set` options, leave `shopt` options changed, define generic logging functions,
  emit output, access the network, or take ownership of application control flow.
- **Runtime operation is pure Bash.**  Logging, formatting, timestamp acquisition,
  redaction, rendering, verification, and emission use Bash language facilities
  and builtins rather than invoking external commands.
- **Standard error is the logging boundary.**  bashlog writes routine log records
  to stderr and leaves transport, persistence, aggregation, and forwarding to the
  caller's environment.
- **Presentation adapts only to TTY state.**  The default renderer is human when
  stderr is a terminal and logfmt otherwise.  bashlog does not try to identify
  systemd, Docker, Podman, containers, CI, or another logging infrastructure.
- **Severity remains durable.**  The canonical level is present in human and
  logfmt output even though threshold filtering is independent of rendering.
- **Human styling is bounded.**  bashlog-owned color and intensity apply only to
  the canonical severity signifier, reset immediately afterward, and never enter
  logfmt output.
- **Redaction is explicit.**  bashlog does not guess what is sensitive, create a
  default context, or apply registered contexts automatically.  Developers create
  rules and decide when to invoke them.
- **Accepted rules become security obligations when invoked.**  Once a developer
  explicitly uses a context, transformation and verification are fail-closed.
- **Primary logging redaction precedes presentation.**  Logger-managed redaction
  operates on the formatted semantic message and tags before human punctuation,
  logfmt escaping, or ANSI decoration.
- **Replacement text is always literal.**  Replacement values are never
  interpreted as shell code, parameter expansion, command substitution, ERE
  backreferences, `&` matched-text substitution, glob expansion, or another
  secondary language.
- **Fixed matching protects exact representable multibyte values.**  Exact
  multibyte Bash strings can be registered without turning their characters into
  pattern syntax.
- **Final verification protects the sink boundary.**  A context-protected logging
  candidate is checked again after rendering and before stderr emission.
- **Registered secret-bearing rule contents are not exposed by a public retrieval
  API.**  bashlog does not intentionally serialize, persist, export, or hand its
  runtime redaction state to helper processes.
- **The security-critical path remains readable.**  bashlog rejects obscurity,
  reversible encoding, `eval`, generated-code tricks, and fake encapsulation as
  substitutes for an actual boundary.

These claims are behavioral.  The project prefers evidence a consumer can inspect
and test over broad statements such as "bashlog securely handles secrets."

## What bashlog Does Not Promise

The limits are part of the contract, not fine print.

bashlog does **not** promise:

- automatic discovery of passwords, tokens, PII, or other sensitive data;
- automatic creation or application of a redaction policy;
- permission to send sensitive information to logging code unnecessarily;
- secure memory, memory locking, or reliable zeroization;
- protection from malicious code already executing in the same Bash interpreter;
- protection from debuggers, `ptrace`, root, kernel compromise, core dumps, or
  equivalent privileged memory inspection;
- protection from caller-side `set -x` tracing that exposes expanded arguments
  before bashlog receives them;
- protection for data the caller writes through another output path;
- Unicode normalization or semantic equivalence between distinct string
  representations;
- locale-independent glob or ERE semantics;
- embedded-NUL support, because ordinary Bash variables cannot faithfully carry
  such data;
- general secret-management, encryption, credential-vault, or secure-enclave
  functionality;
- safety of arbitrary downstream transformations after `bashlog_redact` returns
  a verified value;
- identical visual presentation of color, bold, or dim across terminals and
  themes;
- arbitrary ANSI, background-color, 256-color, or RGB style configuration;
- direct syslog, journald, network, or file delivery;
- automatic discovery of systemd, Docker, Podman, logging drivers, or other
  deployment infrastructure.

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
project.  That tooling is outside the consumer runtime boundary.

## Public API

```text
bashlog_level_get
bashlog_level_set

bashlog_format_get
bashlog_format_set
bashlog_timestamp_get
bashlog_timestamp_set
bashlog_color_get
bashlog_color_set
bashlog_level_style_get
bashlog_level_style_set
bashlog_level_style_reset

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

The normative details, including argument grammar, presentation modes, severity
style configuration, exact logfmt escaping, return statuses, threshold behavior,
matcher semantics, streams, and failure handling, are in
[`doc/bashlog-spec.md`](doc/bashlog-spec.md).

Functions named `__bashlog_*` are implementation details.  Their names are
intentionally readable, but they do not participate in the stable public API.

## Basic Logging

The ordinary logging case remains intentionally small:

```bash
bashlog_info "This is an info message."
bashlog_warning 'configuration file %s is deprecated' "${config_file}"
bashlog_error 'request %s failed with status %s' "${request_id}" "${status}"
```

Routine records go to standard error so standard output remains available for
application data, pipelines, and command substitution.

### Default Adaptive Rendering

The default presentation state is:

```text
format=auto
timestamp=off
color=auto
```

`format=auto` means exactly:

```text
stderr is a TTY      -> human
stderr is not a TTY  -> logfmt
```

bashlog makes that decision from Bash's `[[ -t 2 ]]` result.  It does not probe
the operating system, process tree, cgroups, service manager, container runtime,
or logging driver.

On an interactive terminal, ignoring the ANSI bytes around the severity token:

```text
info: This is an info message.
```

With non-TTY stderr, the same call becomes:

```text
level=info msg="This is an info message."
```

This makes the same script pleasant interactively and machine-oriented when its
stderr is captured by a file, service manager, container runtime, CI system, or
another consumer.

### Explicit Renderer Selection

Callers with a known requirement can override the default:

```bash
bashlog_format_set human
bashlog_color_set never
bashlog_info 'application started'
```

produces:

```text
info: application started
```

while:

```bash
bashlog_format_set logfmt
bashlog_info 'application started'
```

produces:

```text
level=info msg="application started"
```

The configured format is available through:

```bash
bashlog_format_get
```

## Tags

Logging calls accept repeatable tags:

```bash
bashlog_warning --tag api --tag retry 'request delayed'
```

Human rendering:

```text
warning [api] [retry]: request delayed
```

Logfmt rendering:

```text
level=warning tag=api tag=retry msg="request delayed"
```

Input tags use the explicitly ASCII grammar:

```text
[A-Za-z0-9_.:-]+
```

Tag order is preserved.

There is no ambient global tag configuration.  Applications that want a constant
component tag can define a caller-owned wrapper.

## Optional Timestamps

Timestamping is disabled by default.

Enable Bash-native UTC timestamps:

```bash
bashlog_timestamp_set utc
```

or local timestamps:

```bash
bashlog_timestamp_set local
```

UTC values have the form:

```text
2026-08-30T18:40:00Z
```

Local values include a numeric UTC offset:

```text
2026-08-30T14:40:00-0400
```

bashlog uses Bash builtin time formatting.  It does not invoke `date`.  UTC
generation uses function-local timezone state and restores the caller's prior
state when it returns.

Timestamp acquisition occurs only for messages that survive threshold policy.

## Color and Severity Styles

Color modes are:

```text
never
auto
always
```

The default is `auto`.

`bashlog_color_set` controls **whether** bashlog-owned styling is allowed:

- `never` disables it;
- `auto` enables it for human rendering only when stderr is a TTY;
- `always` enables it whenever human rendering is selected.

The logfmt renderer never emits bashlog-owned ANSI, even when color is configured
as `always`.

When styling is enabled, only the canonical severity signifier is styled.  The
ANSI reset immediately follows the severity token; timestamps, tags, punctuation,
message text, and the final newline remain outside the bashlog-owned style span.

The default palette is:

| Severity | Color | Intensity |
| --- | --- | --- |
| `emergency` | red | bold |
| `alert` | red | bold |
| `critical` | red | bold |
| `error` | red | normal |
| `warning` | yellow | normal |
| `notice` | cyan | normal |
| `info` | green | normal |
| `debug` | terminal default | dim |

`bashlog_level_style_set` controls **what** one severity signifier looks like when
styling is enabled:

```bash
bashlog_level_style_set error magenta bold
bashlog_level_style_set warning blue normal
bashlog_level_style_set debug default normal
```

Supported colors are:

```text
default black red green yellow blue magenta cyan white
```

Supported intensities are:

```text
normal bold dim
```

The API accepts symbolic values rather than raw ANSI/SGR strings.  A style of
`default normal` emits no bashlog-owned styling for that severity.

Inspect a level's current style with:

```bash
bashlog_level_style_get critical
```

which prints:

```text
red bold
```

Restore one level or the entire palette with:

```bash
bashlog_level_style_reset error
bashlog_level_style_reset
```

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

The default threshold is `info`.  A message is eligible when its severity number
is less than or equal to the active threshold.

```bash
bashlog_level_set warning

bashlog_info 'suppressed by threshold'
bashlog_error 'emitted'
```

Threshold suppression returns zero and does not construct the message or acquire
a timestamp.

Canonical severity names are case-sensitive.  Short aliases such as `warn`,
`err`, and `crit` are not part of the namespaced API.

## Caller-Owned Short Names

Applications may define ordinary wrappers:

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

The API intentionally does not include `bashlog_die`.  Exiting a sourced
application is application control-flow policy.

## Redaction Requires Developer Participation

Logging is a data-egress boundary.  Passwords, tokens, identifiers, personal
data, and other sensitive values can leak through an otherwise ordinary logging
call.

bashlog provides redaction tooling, but it deliberately does not decide what is
sensitive on the developer's behalf.

Developers must:

1. identify the values or patterns that require protection;
2. create/populate an appropriate context by registering rules;
3. explicitly invoke that context where it is needed.

There is no default redaction context, no heuristic secret discovery, no ambient
current context, and no automatic application of registered contexts.

That explicitness is intentional.  bashlog supplies a strong mechanism and
fail-closed behavior once invoked while leaving application policy with the
person who understands the application.

## Redaction Contexts

Contexts use the lifecycle:

```text
unseen -> active -> destroyed
```

There is no separate empty-context creation call.  The first successfully
registered rule creates a context atomically.

Context names match the explicitly ASCII grammar:

```text
[A-Za-z_][A-Za-z0-9_.:-]*
```

Active contexts are append-only.  Existing rules cannot be edited, reordered, or
individually removed through the public API.

Destroying a context makes it unavailable and prevents reuse of the name for the
remainder of the Bash process:

```bash
bashlog_redaction_context_destroy auth
```

Destruction is **not** secure memory erasure or zeroization.

## Registering Redaction Rules

```text
bashlog_redaction_add CONTEXT MATCHER PATTERN REPLACEMENT
```

The matcher is exactly one of:

```text
fixed
glob
ere
```

For a known password, token, API key, or other exact value, prefer `fixed`:

```bash
password='correct horse battery staple'

bashlog_redaction_add auth fixed \
  "${password}" \
  '[REDACTED PASSWORD]'
```

Rules preserve registration order.  Duplicate matcher/pattern pairs are rejected.
Empty patterns are rejected.  Empty replacements are allowed.

Replacement strings are always literal data.  Values such as `&`, `${USER}`,
`\1`, `$(id)`, `*`, and `?` do not acquire replacement-language semantics.

## Two Redaction Workflows

Both workflows below are first-class public behavior.

### Caller-Managed Redaction

A developer can invoke redaction directly:

```bash
if clean="$(bashlog_redact auth "${message}")"; then
  bashlog_info '%s' "${clean}"
fi
```

The caller owns the composition and must handle the redaction status.  The
subsequent logging call has no selected context and does not rerun the policy.

This form is useful when the transformed value is needed outside the logging
operation or when the caller wants explicit control over the transformation
point.

### Logger-Managed Redaction

A developer can instead pass the context to the logger:

```bash
bashlog_info --context auth \
  'authentication failed for password=%s' \
  "${password}"
```

The logger first constructs the complete printf-style semantic message, applies
the selected context to caller-supplied message/tag fields, renders the protected
values, and finally verifies the completed record before stderr emission.

Under plain human rendering, the example becomes:

```text
info: authentication failed for password=[REDACTED PASSWORD]
```

Under logfmt:

```text
level=info msg="authentication failed for password=[REDACTED PASSWORD]"
```

A call that omits `--context` performs no logger-managed redaction, even when the
process contains registered contexts.

## The `--` Delimiter

`--` ends bashlog logging-option parsing.

Use it when the intended format string begins with `-` or could otherwise be
mistaken for a bashlog option:

```bash
bashlog_info --context auth -- '-token=%s' "${token}"
```

Everything after `--` belongs to the `FORMAT [ARGUMENT ...]` interface.

The delimiter has no redaction semantics of its own.

## Matcher Behavior

### `fixed`

Every character is literal.  Exact non-overlapping occurrences are replaced from
left to right.  Glob and ERE metacharacters have no special meaning.

Exact representable multibyte strings are supported.  bashlog does not normalize
Unicode or perform case folding or canonical-equivalence matching.

### `glob`

`glob` uses a deliberately limited basic Bash pattern language, including `*`,
`?`, and bracket expressions.

Extended-glob operator syntax is rejected so rule meaning does not depend on
ambient `extglob` state.  Patterns capable of matching empty input are rejected.

### `ere`

`ere` uses Bash `[[ STRING =~ ERE ]]` semantics.

Invalid EREs and expressions capable of matching empty input are rejected during
registration.  Capture groups may affect matching, but never create replacement
backreference semantics.

Glob and ERE matching are case-sensitive under the caller's current locale.
bashlog snapshots/restores `nocasematch` around the Bash-native match rather than
letting ambient shell state change the public contract.

## Fail-Closed Verification

Rules are applied once each in registration order using bounded non-overlapping
passes.  bashlog does not repeatedly execute the rule set until a fixed point.

For logger-managed redaction, primary transformation happens before rendering on
the formatted message and each tag.  After rendering, the complete candidate is
checked non-transformingly against the selected context before stderr emission.

Library-generated severity and timestamps are not rewritten by the primary
redaction pass.  If they or renderer-generated bytes collide with an active rule,
the final check suppresses the record rather than rewriting library metadata.

The only redaction-failure diagnostic candidate is:

```text
bashlog: message suppressed
```

Even that diagnostic is verified against an available active context before it is
emitted.

## Logfmt Escaping

The logfmt renderer emits fields in this deterministic order:

```text
[ts=TIMESTAMP] level=LEVEL [tag=TAG ...] msg=MESSAGE
```

`msg` is always double quoted.  Inside quoted values:

| Input | Output |
| --- | --- |
| backslash | `\\` |
| double quote | `\"` |
| tab | `\t` |
| carriage return | `\r` |
| newline | `\n` |
| other ASCII control bytes | `\u00XX` |
| DEL | `\u007F` |

Other representable text, including valid multibyte strings, is preserved.
Embedded NUL remains outside the Bash string model.

Renderer escaping is serialization, not redaction.  When a context is selected,
redaction happens first.

## Shell Tracing Warning

Caller-side tracing can expose secrets before bashlog receives them.

```bash
set -x
bashlog_redaction_add auth fixed "${password}" '[REDACTED]'
```

may cause Bash itself to print the expanded password before entering the function.
No function can retroactively redact text already emitted at the caller's trace
boundary.

## Build and Artifacts

GNU Make is the canonical orchestration surface.

```bash
make deps
make build
```

or:

```bash
make all
```

The build produces three standalone sourceable representations and SHA-256
companions:

```text
dist/bashlog.dev.bash
dist/bashlog.dev.bash.sha256
dist/bashlog.bash
dist/bashlog.bash.sha256
dist/bashlog.min.bash
dist/bashlog.min.bash.sha256
```

Their roles are:

- `bashlog.dev.bash`: assembled source retaining maintained Doxygen comments;
- `bashlog.bash`: ordinary readable artifact with full-line comments removed;
- `bashlog.min.bash`: minified consumer representation.

All three artifacts must satisfy the same public behavior contract.

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

bashlog has no runtime dependency on bashdeps or a particular vendor layout.

A consumer ultimately sources the verified artifact:

```bash
source "${project_root}/vendor/bashlog.bash"

bashlog_info 'application started'
```

## Testing

The behavior/security suite is under `tests/contract/`.

`make test` executes the same suite against:

- `dist/bashlog.dev.bash`;
- `dist/bashlog.bash`;
- `dist/bashlog.min.bash`.

The suite covers source-time behavior, severity/threshold semantics, adaptive
human/logfmt presentation, tags, timestamp and color configuration, configurable
severity-token styles, exact logfmt escaping, both explicit redaction workflows,
context lifecycle, fixed/glob/ERE semantics, multibyte exact matching, ambient
shell-state isolation, fail-closed rule interactions, safe diagnostics,
unavailable contexts, and the no-external-runtime-command boundary.

Security tests assert absence as well as presence.  A replacement marker appearing
is not sufficient evidence if the protected original leaked elsewhere.

CI additionally runs a representative compatibility contract against all three
artifacts under Bash 4.3, including representative severity style configuration
and rendering.

## Documentation Model

bashlog treats documentation as part of the architecture.

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

Generated Doxygen reference output lives under `doc/reference/` and is ephemeral.

## Architectural Decisions

The complete ADR index is in [`doc/adr/README.md`](doc/adr/README.md), and the
concise decision map is in [`doc/decisions.md`](doc/decisions.md).

ADR-013 through ADR-024 establish the accepted sourceable-library, runtime-purity,
namespaced-API, logging, redaction, matcher, auditability, and fail-closed
foundations.  ADR-025 and ADR-026 define timestamps, tags, adaptive human/logfmt
rendering, stderr environment composition, and semantic-redaction-before-rendering
ordering.  ADR-027 defines the severity-signifier-only styling boundary and the
symbolic per-level override API.

Architectural conflicts should be resolved explicitly rather than allowing
implementation convenience to silently redefine the contract.

## License and Contributions

This project is dedicated to the public domain under CC0 1.0 Universal.  See
`LICENSE` and `CONTRIBUTING.md` for details, and `CODE_OF_CONDUCT.md` for project
collaboration expectations.
