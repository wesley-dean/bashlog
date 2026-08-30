# bashlog Public Behavior Specification

Status: Accepted

Date: 2026-08-30

## Purpose

This document defines the intended observable public behavior of bashlog.

Architecture Decision Records under `doc/adr/` explain why consequential design
choices exist.  This specification translates those choices into a concrete
public contract: function names, argument ordering, outputs, return statuses,
severity semantics, presentation modes, redaction-context selection, and failure
behavior.

The specification is intentionally precise.  A caller should not have to inspect
implementation details to determine what a public function means, and an
implementer should not have to invent public semantics while writing code.

This specification is **Accepted** as the normative public contract for the first
functional release.  Runtime conformance must still be demonstrated by tests
against the artifacts intended for publication.

## Normative Language

The terms MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT, and MAY are used
normatively.

Where this specification conflicts with an Accepted ADR, the ADR governs and the
conflict must be corrected.  The specification defines observable behavior within
the boundaries established by the Accepted ADR corpus.

## Runtime Baseline

bashlog targets Bash 4.3 or newer.

Normal runtime operation uses Bash language facilities and builtins only.  The
library does not invoke external commands for loading, level handling, message
formatting, timestamp acquisition, redaction, rendering, verification, or
emission.

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
- infer container, init-system, or logging infrastructure;
- or assume application error-handling or exit policy.

The implementation may create clearly namespaced Bash variables and functions.
Internal `__bashlog_*` names are implementation details by convention and are not
private or access-controlled by Bash.

## Public API Overview

The public API is:

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

No other function participates in the stable public contract merely because it
exists in a generated artifact.

The first stable release SHOULD treat documented `bashlog_*` functions as
semantic-version compatibility surface.  `__bashlog_*` functions and variables
MUST NOT be treated as stable interfaces.

## Return Statuses

The API uses a small shared status vocabulary.  The values intentionally follow
familiar `sysexits` numeric conventions where that improves recognition, but
bashlog does not depend on a system `sysexits.h` file or external utility.

| Status | Meaning |
| ---: | --- |
| `0` | The requested operation succeeded.  For logging calls, this also includes intentional suppression by the configured level threshold. |
| `64` | The caller supplied invalid arguments, an invalid level, an invalid tag, an invalid context identifier, an unknown option, an invalid presentation mode or style, or otherwise invalid API syntax. |
| `65` | A proposed redaction rule is invalid, duplicate, unsatisfiable, or cannot be accepted under its matcher contract. |
| `69` | A specifically requested redaction context is unavailable because it is unknown or destroyed. |
| `70` | Redaction, final verification, timestamp acquisition, rendering, or another internal transformation could not be completed safely. |
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
of the namespaced API.

Applications MAY define their own wrappers.

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

Threshold suppression occurs before `printf`-style message construction and
before timestamp acquisition.  This avoids unnecessary creation and copying of a
message or metadata that will not cross a bashlog sink.

Logging option syntax, tags, and an explicitly requested context remain caller
contract.  Invalid syntax, an invalid tag, or an unavailable requested context
MUST NOT silently become successful merely because the severity would otherwise
be suppressed.

Severity is semantic state used for filtering.  The textual severity token is a
separate presentation concern, but both supported renderers preserve the
canonical severity so classification remains durable after the record leaves
bashlog.

## `bashlog_level_get`

### Synopsis

```text
bashlog_level_get
```

### Behavior

Writes the active canonical severity name to standard output followed by one
newline.

### Return Status

- `0`: level written successfully.
- `64`: arguments were supplied.

## `bashlog_level_set`

### Synopsis

```text
bashlog_level_set LEVEL
```

`LEVEL` may be a canonical severity name or the corresponding integer `0` through
`7`.  Names are case-sensitive.  Aliases are not accepted.

On success, the threshold changes for subsequent logging calls in the current
Bash process and the function produces no output.  On failure, the previous
threshold remains unchanged.

### Return Status

- `0`: threshold changed.
- `64`: missing, extra, or invalid level argument.

## Presentation Configuration

bashlog has three global presentation controls:

```text
format=auto
timestamp=off
color=auto
```

Those are the defaults after sourcing.  Per-severity human-token style is a
separate presentation state described below.

All presentation setters validate atomically.  Invalid input returns `64`, emits
no routine output, and leaves the previous setting unchanged.

### `bashlog_format_get` and `bashlog_format_set`

```text
bashlog_format_get
bashlog_format_set MODE
```

`MODE` MUST be exactly one of:

```text
auto
human
logfmt
```

`bashlog_format_get` writes the configured mode followed by one newline.  It does
not resolve `auto` into the renderer that would be selected for the current file
descriptor state.

`auto` means exactly:

```text
stderr is a TTY      -> human
stderr is not a TTY  -> logfmt
```

The decision is made for each eligible logging operation using Bash
`[[ -t 2 ]]`.  bashlog does not inspect systemd, journald, Docker, Podman,
Kubernetes, Swarm, OpenRC, cgroups, process ancestry, operating-system identity,
or environment markers to choose a renderer.

`human` always selects the human renderer.  `logfmt` always selects the logfmt
renderer.

### `bashlog_timestamp_get` and `bashlog_timestamp_set`

```text
bashlog_timestamp_get
bashlog_timestamp_set MODE
```

`MODE` MUST be exactly one of:

```text
off
utc
local
```

The default is `off`.

`utc` generates a Bash-native current-time value with second precision:

```text
YYYY-MM-DDTHH:MM:SSZ
```

`local` generates a Bash-native local-time value with second precision and a
numeric UTC offset:

```text
YYYY-MM-DDTHH:MM:SS+HHMM
```

Timestamp generation MUST use Bash builtin time formatting and MUST NOT invoke
external `date` or another helper.  UTC generation may use function-local
exported `TZ` state; caller-visible timezone value and export state MUST be
preserved after the call.

Timestamp acquisition occurs only after syntax, explicitly requested context,
tag, and threshold validation establish that the record is eligible for message
construction and rendering.

The contract does not include fractional seconds.

### `bashlog_color_get` and `bashlog_color_set`

```text
bashlog_color_get
bashlog_color_set MODE
```

`MODE` MUST be exactly one of:

```text
never
auto
always
```

The default is `auto`.

Color mode controls whether bashlog-owned severity styling may be emitted by the
human renderer:

- `never` emits no bashlog-owned ANSI SGR sequences;
- `auto` uses the configured severity style only when standard error is a TTY
  according to `[[ -t 2 ]]`;
- `always` uses the configured severity style whenever the human renderer is
  selected.

The logfmt renderer NEVER emits bashlog-owned ANSI sequences, even when the color
mode is `always`.

Global color mode and per-level style are intentionally independent.  Color mode
answers **whether** styling is permitted; the level-style API answers **what** the
severity signifier looks like when styling is permitted.

### Severity Token Style

The public style API is:

```text
bashlog_level_style_get LEVEL
bashlog_level_style_set LEVEL COLOR INTENSITY
bashlog_level_style_reset [LEVEL]
```

`LEVEL` accepts the same canonical severity names and integers from `0` through
`7` accepted by `bashlog_level_set`.  Numeric and named forms address the same
per-severity style state.

`COLOR` MUST be exactly one of:

```text
default
black
red
green
yellow
blue
magenta
cyan
white
```

`INTENSITY` MUST be exactly one of:

```text
normal
bold
dim
```

The default palette is:

| Severity | Color | Intensity | Effective SGR |
| --- | --- | --- | --- |
| `emergency` | `red` | `bold` | `1;31` |
| `alert` | `red` | `bold` | `1;31` |
| `critical` | `red` | `bold` | `1;31` |
| `error` | `red` | `normal` | `31` |
| `warning` | `yellow` | `normal` | `33` |
| `notice` | `cyan` | `normal` | `36` |
| `info` | `green` | `normal` | `32` |
| `debug` | `default` | `dim` | `2` |

Supported foreground color codes are the ordinary ANSI values `30` through `37`.
`default` contributes no explicit foreground-color code.  Intensity contributes
no code for `normal`, `1` for `bold`, and `2` for `dim`.  When both intensity and
foreground color contribute a code, intensity precedes color, for example
`bold red` -> `1;31`.

A configured style of `default normal` emits no bashlog-owned SGR sequence for
that severity.  This allows a caller to leave one signifier visually plain even
while global color mode permits styling.

#### `bashlog_level_style_get`

```text
bashlog_level_style_get LEVEL
```

Writes exactly:

```text
COLOR INTENSITY
```

followed by one newline for the current style of the selected severity.

For example, under the defaults:

```text
bashlog_level_style_get critical
red bold
```

Return status is `0` on success and `64` for an invalid argument count or level.

#### `bashlog_level_style_set`

```text
bashlog_level_style_set LEVEL COLOR INTENSITY
```

Atomically replaces the selected severity's style for subsequent human-rendered
records.  Invalid level, color, intensity, or argument count returns `64`, emits
no routine output, and leaves the prior style unchanged.

For example:

```bash
bashlog_level_style_set error magenta bold
bashlog_level_style_set warning blue normal
bashlog_level_style_set debug default normal
```

Raw ANSI escape sequences, raw numeric SGR fragments, arbitrary attribute lists,
background colors, 256-color indexes, and RGB/true-color values are not accepted
by this contract.

#### `bashlog_level_style_reset`

```text
bashlog_level_style_reset [LEVEL]
```

With one valid level argument, restores only that severity to the library default
palette.  With no arguments, restores all eight levels to their library defaults.

More than one argument or an invalid level returns `64` and leaves style state
unchanged.

#### Style Placement

When styling is enabled, bashlog-owned ANSI applies only to the canonical
severity token.  The reset sequence immediately follows that token.

Conceptually:

```text
[TIMESTAMP] STYLE_START LEVEL STYLE_RESET [TAG] [TAG]: MESSAGE
```

The timestamp, spaces, tags, punctuation, colon, message body, and final newline
are outside bashlog's severity-style span.

For example, an explicitly human error record with `error=magenta bold` is
serialized conceptually as:

```text
\e[1;35merror\e[0m [api]: request failed
```

Only `error` is styled.  `[api]: request failed` is not.

## Logging Call Syntax

The generic logger and every severity helper use the same option and message
shape.

### Generic Logger

```text
bashlog_log LEVEL [--context CONTEXT] [--tag TAG ...] [--] FORMAT [ARGUMENT ...]
```

### Severity Helpers

```text
bashlog_info [--context CONTEXT] [--tag TAG ...] [--] FORMAT [ARGUMENT ...]
bashlog_warning [--context CONTEXT] [--tag TAG ...] [--] FORMAT [ARGUMENT ...]
```

The same shape applies to every severity helper.

Before the format string begins:

- `--context CONTEXT` selects one active redaction context for this logging call;
- `--tag TAG` adds one caller-supplied tag and MAY be repeated;
- `--` ends bashlog option parsing.

`--context` and `--tag` MAY appear in either order before the format string or
`--`.  At most one `--context` is accepted.  A duplicate context option returns
`64`.

`--` is required when the intended format string begins with `-` or could
otherwise be interpreted as a bashlog option.  It MAY be used unconditionally for
clarity.

For example:

```bash
bashlog_info --context secrets -- '-token=%s' "${token}"
```

The delimiter has no redaction meaning.  It separates bashlog options from the
`FORMAT [ARGUMENT ...]` interface.

An unrecognized leading option returns `64` without emitting the caller's
message.

The ordinary case remains intentionally terse:

```bash
bashlog_info "This is an info message."
```

No context is inferred for that call.

## Tags

A tag supplied through `--tag TAG` MUST initially match the explicitly ASCII
grammar:

```text
[A-Za-z0-9_.:-]+
```

An empty tag, whitespace, bracket characters, control characters, or non-ASCII
characters therefore return `64` at the call boundary.

Tags preserve exact argument order.

When a logging call explicitly selects a redaction context, each caller-supplied
tag is transformed and verified independently under that same context before
rendering.  A literal replacement may cause the transformed tag to no longer
match the input tag grammar.  That does not undo a successful redaction:

- the human renderer places the resulting value inside its documented tag
  brackets;
- the logfmt renderer quotes and escapes a transformed tag that no longer matches
  the unquoted token grammar.

No ambient or global tag configuration is part of this contract.  Applications
that need a constant component tag MAY use caller-owned wrapper functions.

## `printf`-Style Message Construction

`FORMAT` and subsequent arguments use Bash builtin `printf` formatting semantics.
The implementation SHALL construct the complete semantic message in shell state
before primary logging-pipeline redaction or rendering.

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

## Human Renderer

The human renderer is compact and human-oriented.

With timestamping disabled and no tags:

```text
LEVEL: MESSAGE
```

With tags:

```text
LEVEL [TAG] [TAG]: MESSAGE
```

With a timestamp:

```text
[TIMESTAMP] LEVEL [TAG]: MESSAGE
```

Examples without ANSI decoration:

```text
info: application started
warning [database]: connection delayed
[2026-08-30T18:40:00Z] error [api]: request failed
```

The canonical lowercase severity is always present.  When global color mode
permits styling, only that severity token receives the configured per-level
foreground color and intensity.  bashlog resets SGR state immediately after the
severity token before tags, punctuation, or message text are appended.

Human rendering preserves representable message bytes according to Bash string
semantics.  In particular, an embedded newline in the message remains an embedded
newline.  The human renderer is not a generic log-injection sanitizer.

bashlog appends exactly one final newline after the completed record when emitting
it to standard error.

## Logfmt Renderer

The machine-oriented renderer uses a deliberately constrained logfmt profile.
logfmt is established prior art rather than a formally standardized protocol, so
this specification owns the exact representation bashlog emits.

Field order is deterministic:

```text
[ts=TIMESTAMP] level=LEVEL [tag=TAG ...] msg=MESSAGE
```

The fields are:

- `ts`, present only when timestamping is enabled;
- `level`, always present with the canonical lowercase severity;
- zero or more repeated `tag` fields in caller order;
- `msg`, always present with the complete formatted message.

Examples:

```text
level=info msg="application started"
level=warning tag=database msg="connection delayed"
ts=2026-08-30T18:40:00Z level=error tag=api msg="request failed"
```

`ts` and `level` are library-generated safe tokens and are emitted unquoted.
A tag that satisfies the tag token grammar is emitted unquoted.  A transformed
tag that no longer satisfies that grammar is quoted using the same string encoder
used for `msg`.

`msg` is always enclosed in double quotes, including an empty message and a
message that could otherwise be represented as an unquoted token.  This keeps the
message boundary deterministic.

Per-level severity style configuration has no effect on logfmt bytes.  The
logfmt renderer never emits bashlog-owned ANSI, regardless of global color mode or
per-level style state.

### Logfmt String Escaping

Within a quoted value, bashlog emits these exact escapes:

| Input | Encoded bytes |
| --- | --- |
| backslash | `\\` |
| double quote | `\"` |
| horizontal tab | `\t` |
| carriage return | `\r` |
| line feed | `\n` |
| other ASCII controls `0x01` through `0x1F` | `\u00XX` |
| DEL `0x7F` | `\u007F` |

`XX` is uppercase hexadecimal in bashlog output.  NUL remains outside the Bash
string contract.

Other representable characters, including valid multibyte text, are preserved as
represented by Bash.

The escaping profile intentionally follows established logfmt/Go quoted-string
prior art for quotes, backslashes, standard controls, and `\u00XX` control
encoding.  Renderer escaping is a serialization step, not a redaction mechanism.

The logfmt renderer emits one physical log line for representable message data
because embedded tabs, carriage returns, newlines, and other ASCII control bytes
are escaped.

## Logging Output Stream and Environment Boundary

All public logging functions emit their final record to **standard error**.

This applies to every severity.  bashlog does not use standard output for routine
logging because standard output is commonly an application's data channel in
shell programs, pipelines, and command substitutions.

A caller may redirect standard error using ordinary shell redirection.

Standard error is the universal bashlog sink.  bashlog does not attempt to infer
what consumes file descriptor 2.  The surrounding environment may send that
stream to a terminal, systemd journal, Docker or Podman logging driver, CI log,
cron capture, file, pipe, orchestrator, or another destination.

The default `format=auto` behavior adapts only to whether file descriptor 2 is a
TTY.  It does not identify the downstream logging infrastructure.

The API does not provide implicit:

- file sinks;
- caller-selected file-descriptor sinks;
- syslog transport;
- journald socket transport;
- TCP or UDP log transport;
- `logger` invocation;
- or another external-command sink.

A future direct remote-syslog or alternate-sink feature requires separate
architectural review.

## Redaction Is Explicit and Developer-Owned

Redaction is opt-in defense in depth.

bashlog does not decide what developers may log, does not identify sensitive data
heuristically, does not create a default redaction context, and does not apply
registered contexts automatically.

The developer owns three decisions:

1. what application data is sensitive;
2. which rules belong in a redaction context;
3. when that context should be invoked.

Registering a context creates an available mechanism.  It does not create ambient
logging policy.

This explicitness is intentional.  Logging is a data-egress boundary.  Ordinary
`debug`, `info`, or error-reporting calls can leak passwords, tokens, identifiers,
personal data, or other sensitive values if developers do not account for those
values.  bashlog provides a strong mechanism when invoked without pretending it
can replace application knowledge and developer judgment.

## Two Explicit Redaction Workflows

Callers may choose either of two supported workflows.

### Caller-Managed Redaction

The caller MAY invoke `bashlog_redact` directly, handle its status, and pass the
result to an ordinary logging call without `--context`.

For example:

```bash
if redacted_message="$(bashlog_redact secrets "${message}")"; then
  bashlog_info '%s' "${redacted_message}"
fi
```

The caller owns this composition.  The caller must handle redaction failure,
avoid reintroducing sensitive data afterward, and separately protect any other
caller-supplied values that require redaction.

The subsequent logging call has no selected context, so it does not rerun that
context's transformation or final verification.

This workflow is useful when the caller wants the transformed value for another
purpose or wants exact control over when redaction occurs.

### Logger-Managed Redaction

The caller MAY instead pass:

```text
--context CONTEXT
```

to the logging function.

For example:

```bash
bashlog_info --context secrets 'token=%s' "${token}"
```

Under this workflow, bashlog owns the composition of message construction,
redaction, rendering, final verification, and standard-error emission.  Once the
context is explicitly selected, redaction and verification failures are
fail-closed.

A logging call without `--context` performs no logging-pipeline redaction and is
not inspected against unrelated registered contexts.  The data may nevertheless
already have been redacted by caller-managed use of `bashlog_redact`.

There is no ambient current redaction context.

## Logging Pipeline

For a syntactically valid call, the observable logger-managed processing model is:

```text
validate call, tags, and explicitly requested context, if any
    -> severity/threshold decision
    -> printf-style message construction
    -> acquire optional Bash-native timestamp
    -> assemble semantic fields
    -> if --context was selected:
         transform and verify formatted message
         transform and verify each caller-supplied tag
    -> select human or logfmt renderer
    -> serialize fields and add renderer-owned presentation
    -> if --context was selected:
         finally verify the complete rendered candidate
    -> emit to standard error
```

Primary redaction occurs on caller-supplied semantic data **before** human
punctuation, logfmt quoting/escaping, or ANSI decoration.

The fields transformed during logger-managed primary redaction are:

- the complete formatted message;
- each caller-supplied tag, independently and in argument order.

Canonical severity and a bashlog-generated timestamp are library-owned metadata.
They are not rewritten by the primary redaction transformation.  When a context
is selected, they are still part of the completed candidate checked by final
non-transforming verification.

Per-level severity style is library-owned presentation metadata.  It is applied
only after primary redaction has completed, so styling cannot split or disguise a
caller value before matching.  Any resulting bashlog-owned ANSI bytes are part of
the completed candidate seen by final verification when a context is selected.

A pattern is not promised to span multiple logical fields or to depend on
renderer punctuation that does not exist during primary redaction.

If transformation or semantic verification of any protected field fails, the
entire logging operation fails closed.  bashlog does not emit a partially
protected record.

A threshold-suppressed valid call returns `0` and emits nothing.

## Redaction Context Selection

A logger-managed call requests redaction only by specifying:

```text
--context CONTEXT
```

The context name must match:

```text
[A-Za-z_][A-Za-z0-9_.:-]*
```

The grammar is explicitly ASCII.

A requested context must already be active.

If a logging call explicitly names a context that is invalid, unknown, or
destroyed:

- the caller's message MUST NOT be emitted;
- the operation returns `64` for an invalid identifier or `69` for an unknown or
  destroyed valid identifier;
- a fixed safe diagnostic MAY be written as defined below.

An omitted context is different from an unavailable requested context.  Omission
means "log without logger-managed redaction."  An unavailable requested context
means the caller attempted to rely on a policy that bashlog cannot provide, so the
call fails closed.

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
There is no separate public empty-context creation operation and no default or
synthetic context.

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
with `65` because the rule is predictably incapable of satisfying verification on
its own replacement.

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
continues after that matched input.

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

The contract supports ordinary Bash pattern elements such as:

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
Security against content reintroduced by later replacements is provided by
verification rather than iterative rewriting.

## Redaction Verification

The standalone `bashlog_redact` API performs one ordered transformation over its
exact caller-supplied string and then verifies that transformed result against
every active rule in the selected context.

Logger-managed redaction performs that same transform-and-verify operation on the
formatted message and each tag independently before rendering.

After human or logfmt rendering is complete, a logging call that selected a
context performs one additional **non-transforming** verification of the complete
candidate immediately before standard-error emission.

This final check includes library-generated severity, optional timestamp,
renderer punctuation, logfmt escaping, and human ANSI decoration where present.
It is defense in depth; it is not the primary redaction mechanism.

A candidate is eligible for emission only when none of the selected context's
active rules matches it at the applicable verification point.

If:

- any active rule still matches;
- a matcher cannot be evaluated safely;
- or verification cannot otherwise establish that the candidate satisfies the
  selected policy;

bashlog MUST NOT emit the protected candidate.  The operation returns `70`.

The library does not attempt iterative repair after verification fails.

This means a rule that collides with library-generated or renderer-generated text
may conservatively suppress a logger-managed record.  For example, a fixed rule
matching the textual severity in the completed candidate does not rewrite the
severity; final verification suppresses that record instead.

When no logging context is explicitly selected, the logging pipeline performs no
redaction verification against registered contexts.

## Redaction Failure Diagnostic

When an operation must suppress protected data because redaction or verification
cannot be completed safely, the only permitted diagnostic candidate is:

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

- the context cannot be used for logging or `bashlog_redact`;
- no new rules can be appended to that context name;
- the name cannot be reused during the current Bash process;
- bashlog removes its active references to rule data as far as the implementation
  can intentionally control;
- non-secret tombstone state MAY remain so name reuse can be rejected.

The operation applies to the entire context.  There is no public individual-rule
deletion operation.

### Security Limitation

Context destruction is **not** secure memory erasure.

bashlog cannot prove that Bash, libc, the operating system, a core dump, or
historical copies no longer contain prior string bytes.  Documentation and
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
severity, timestamp, tag, color, logfmt syntax, or logging emission.

This function is the caller-managed counterpart to logger-managed `--context`.
It also supports caller-owned sinks outside bashlog.

### Behavior

On success:

1. validates and resolves the requested active context;
2. applies every rule once in registration order;
3. performs final verification against every active rule;
4. writes the verified redacted value to standard output with **no automatically
   added newline**.

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
context's active matcher rules at the point of verification.  It does not claim
that the string is generally non-sensitive, safe for every audience, safe for
every downstream parser, or protected from later caller transformations.

If the caller modifies the returned string or combines it with additional data,
that later result has not been verified by bashlog unless it is passed through a
redaction boundary again.

## Severity Helpers

Each severity helper is semantically equivalent to `bashlog_log` with its level
fixed to the corresponding canonical severity.

For example:

```text
bashlog_info [--context CONTEXT] [--tag TAG ...] [--] FORMAT [ARGUMENT ...]
```

is equivalent in logging behavior to:

```text
bashlog_log info [--context CONTEXT] [--tag TAG ...] [--] FORMAT [ARGUMENT ...]
```

The helpers MUST NOT implement alternate rendering, redaction, verification, or
emission paths.

## No `bashlog_die` in the Public Contract

The public API does not include `bashlog_die`.

Exiting a sourced application's shell is control-flow policy.  bashlog provides
logging primitives; the caller chooses whether and how to exit.

A future namespaced exit helper would require explicit review because `exit` from
a sourced library function terminates the caller's shell process.

## No Automatic Host or Deployment Metadata

Optional Bash-native timestamps are logging metadata owned by this contract.
Their existence does not authorize broader host inspection.

bashlog does not automatically acquire:

- hostname;
- process identifier;
- username;
- Git revision;
- application name;
- systemd unit;
- container identity;
- orchestrator metadata;
- or logging-driver metadata.

Callers may provide such values explicitly as message data when appropriate.
External commands used to obtain them remain caller-owned behavior.

## No Built-In External Sink

The API does not invoke `logger`, `tee`, network clients, or other helper
commands.

A caller may deliberately compose an external integration:

```bash
safe="$(bashlog_redact auth "${message}")" || exit
logger -- "${safe}"
```

The `logger` invocation is caller-owned.  Any metadata, buffering, transport,
security, or failure semantics introduced after `bashlog_redact` are outside the
bashlog sink contract.

Running under systemd, Docker, Podman, CI, cron, or another supervisor may cause
that environment to capture bashlog's normal standard-error stream.  That is
composition through stderr, not a bashlog-specific transport.

## Security Promises

Subject to the governing ADRs and exact matcher semantics above, the public
contract promises:

1. A rule accepted into a context is a security obligation for bashlog operations
   that explicitly invoke that context.
2. bashlog does not silently apply registered contexts to unrelated logging calls.
3. Logger-managed primary redaction occurs on caller-supplied semantic message and
   tag fields before presentation encoding.
4. A context-protected logging candidate is finally verified after rendering and
   before standard-error emission.
5. A redaction or verification failure never falls back to emitting the original
   protected candidate.
6. Successful verification means the candidate at that verification boundary
   matches none of the selected context's active rules.
7. Fixed replacements are exact and literal; replacement text is never evaluated
   or interpreted as a secondary language.
8. No public getter, list, serialization, or inspection API returns secret-bearing
   rule contents.
9. Runtime redaction does not invoke external helper commands.
10. bashlog does not intentionally persist or export registered redaction state.
11. Exact representable multibyte values are supported by the fixed matcher.
12. All severity helpers converge through the same logging, presentation, and
    optional redaction pipeline.
13. Caller-configured severity styling is presentation-only, bounded to symbolic
    values, and cannot cause raw caller-supplied ANSI to enter bashlog through the
    style API.

## Explicit Non-Promises

The public contract does **not** promise:

1. automatic identification of passwords, tokens, PII, or other sensitive data;
2. creation of a default redaction policy or automatic application of registered
   contexts;
3. secure memory, memory locking, or reliable zeroization;
4. protection from malicious code executing in the same Bash interpreter;
5. protection from `ptrace`, root, debuggers, core dumps, kernel compromise, or
   equivalent privileged memory access;
6. protection from caller-side `set -x` exposure before bashlog receives function
   arguments;
7. protection for data the caller writes through another path;
8. retroactive protection for data emitted before a rule was registered;
9. Unicode normalization or semantic equivalence for distinct byte sequences;
10. locale-independent glob or ERE semantics;
11. embedded-NUL support;
12. generic log-injection prevention for human-rendered caller message data;
13. secret management, encryption, credential storage, or vault functionality;
14. safety of downstream transformations performed after successful
    `bashlog_redact` output;
15. direct syslog, journald, network, or file delivery;
16. automatic discovery of systemd, containers, logging drivers, or other
    deployment infrastructure;
17. byte-identical `format=auto` output when stderr changes between TTY and
    non-TTY conditions;
18. identical visual presentation of color, bold, or dim attributes across
    terminal emulators and themes;
19. background colors, arbitrary SGR attributes, 256-color, or RGB style
    configuration through the initial level-style API.

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

## Examples

### Ordinary Logging

```bash
bashlog_info "This is an info message."
```

On an interactive terminal under the defaults, the human renderer is selected and
the severity token is colorized.  Ignoring ANSI bytes, the visible record is:

```text
info: This is an info message.
```

With non-TTY stderr under the defaults, the same call emits:

```text
level=info msg="This is an info message."
```

### Explicit Human Output

```bash
bashlog_format_set human
bashlog_color_set never
bashlog_warning --tag database 'connection delayed'
```

Expected standard-error record:

```text
warning [database]: connection delayed
```

### Override One Severity Signifier

```bash
bashlog_format_set human
bashlog_color_set always
bashlog_level_style_set error magenta bold
bashlog_error --tag api 'request failed'
```

The human renderer emits the equivalent of:

```text
\e[1;35merror\e[0m [api]: request failed
```

Only the canonical `error` token receives bashlog-owned styling.  The tag,
punctuation, and message remain outside the style span.

Restore the library default for that one severity with:

```bash
bashlog_level_style_reset error
```

or restore the complete palette with:

```bash
bashlog_level_style_reset
```

### Explicit Logfmt Output

```bash
bashlog_format_set logfmt
bashlog_warning --tag api --tag retry 'request delayed'
```

Expected standard-error record:

```text
level=warning tag=api tag=retry msg="request delayed"
```

### Set the Threshold

```bash
bashlog_level_set warning
bashlog_info 'not emitted'
bashlog_error 'emitted'
```

The info call returns `0` but writes nothing because it is below the configured
threshold.

### Register and Use a Fixed Secret Through the Logger

```bash
password='correct horse battery staple'

bashlog_redaction_add auth fixed \
  "${password}" \
  '[REDACTED PASSWORD]'

bashlog_info --context auth \
  'authentication failed for password=%s' \
  "${password}"
```

The developer created the context and explicitly selected it for the log call.
With explicit human output and color disabled, the record is:

```text
info: authentication failed for password=[REDACTED PASSWORD]
```

Under default non-TTY rendering, the equivalent record is:

```text
level=info msg="authentication failed for password=[REDACTED PASSWORD]"
```

### Caller-Managed Redaction

```bash
safe_message="$(bashlog_redact auth "${message}")" || exit
bashlog_info '%s' "${safe_message}"
```

The logging call does not need `--context` for the same value because the caller
already chose and handled the redaction operation.

### Use `--` for a Leading-Dash Format

```bash
bashlog_info --context auth -- '-token=%s' "${token}"
```

Everything after `--` belongs to the printf-style message interface.

### Literal Replacement Characters

```bash
bashlog_redaction_add auth fixed 'secret' '&-${USER}-\1-$(id)'
bashlog_info --context auth '%s' 'value=secret'
```

The replacement is literal.  No user-name expansion, command substitution,
backreference, or matched-text substitution occurs.

## Features Deliberately Outside This Contract

The following remain deferred:

- hostnames generated by bashlog;
- process identifiers generated by bashlog;
- syslog facilities;
- built-in `logger` integration;
- direct journald integration;
- file sinks;
- caller-selected sink file descriptors;
- network sinks;
- automatic environment or Git metadata;
- aliases for canonical severity names;
- generic short functions installed by the library;
- a namespaced `bashlog_die` control-flow helper;
- ambient/global tags;
- caller-defined render templates;
- JSON Lines rendering;
- background-color severity styling;
- arbitrary ANSI/SGR severity styling;
- 256-color or RGB/true-color severity styling;
- context rule listing;
- individual rule deletion or mutation;
- context name reuse after destruction;
- Unicode normalization;
- capture-based or expression-based replacement;
- extglob redaction syntax;
- automatic secret/PII discovery.

Deferral is intentional.  A future feature must preserve the security and
responsibility boundaries rather than expanding the public surface merely because
an implementation is possible.

## Required Test Implications

Before this specification can be described as implemented behavior, tests SHOULD
demonstrate at minimum:

- source-time silence and absence of trap/shell-option/shopt mutation;
- Bash 4.3 representative behavior;
- default presentation state `auto` / `off` / `auto`;
- atomic validation of presentation setters;
- default per-level style palette and query behavior;
- numeric and named level references address the same severity style;
- per-level style overrides validate atomically;
- one-level and all-level reset semantics;
- `default normal` emits no bashlog-owned ANSI for that severity;
- `format=auto` selects logfmt for non-TTY stderr and human for TTY stderr;
- explicit human and logfmt selection overrides automatic selection;
- exact human severity, tag, timestamp, and style behavior;
- severity styling is bounded to the canonical signifier and resets immediately
  afterward;
- logfmt never contains bashlog-owned ANSI color or intensity, including after a
  per-level override;
- exact deterministic logfmt field ordering;
- exact logfmt escaping for quotes, backslashes, tabs, carriage returns,
  newlines, other ASCII controls, and representative multibyte text;
- timestamp shape, caller timezone preservation, and no timestamp acquisition for
  threshold-suppressed calls;
- tag validation is explicitly ASCII and tag order is preserved;
- threshold boundaries for every severity;
- logging functions do not write routine logs to standard output;
- invalid call syntax returns the documented status and does not emit caller data;
- unknown and destroyed requested contexts fail closed;
- registered contexts remain inert for logging calls that omit `--context`;
- caller-managed `bashlog_redact` followed by ordinary logging works as
  documented;
- logger-managed `--context` redacts the formatted semantic message before
  rendering;
- logger-managed `--context` protects tags before rendering;
- library-generated severity is not transformed by primary redaction;
- final verification includes the complete rendered record for context-protected
  logging calls;
- context creation is atomic with first successful registration;
- active context policy is append-only;
- duplicate rules are rejected;
- empty patterns are rejected and empty replacements are accepted;
- replacement strings containing `&`, backslashes, `$()`, `${...}`, glob
  metacharacters, and ERE-like text remain literal;
- fixed matching handles multiple and adjacent occurrences;
- fixed matching handles representative UTF-8 values as exact input sequences;
- normalization-equivalent but byte-distinct strings are not falsely promised to
  match;
- glob and ERE zero-length-capable patterns are rejected;
- invalid ERE registration does not create or mutate context state;
- extglob semantics do not depend on ambient `shopt` state;
- rule ordering is deterministic;
- later replacements cannot reintroduce earlier protected content and still be
  emitted;
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
expected replacement appeared while the original protected value also leaked
elsewhere.

## Governing Decisions

This accepted specification is derived primarily from:

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
- ADR-025: Optional Presentation Metadata, Tags, and Color
- ADR-026: Adaptive Human/Logfmt Rendering and Environment-Agnostic Stderr
  Transport
- ADR-027: Configurable Severity Token Styles

ADR-026 supersedes the portions of ADR-017 and ADR-024 that assumed primary
logging redaction transforms a complete rendered `level: message` candidate.
Their common-pipeline, opt-in-security, fail-closed, and safe-diagnostic principles
remain in force.

If implementation experience demonstrates that this specification cannot satisfy
a governing architectural promise clearly and readably on Bash 4.3, the project
should revisit the relevant ADR rather than quietly weakening the documented
contract.
