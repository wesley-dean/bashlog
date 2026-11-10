# bashlog

bashlog is a sourceable pure-Bash logging library built around predictable
behavior, explicit developer-owned redaction, and a small auditable runtime.

The project is currently **pre-release**.  It targets Bash 4.3 or newer and uses
only Bash language facilities and builtins at runtime.

## Quick Start

Source a built or pinned bashlog artifact, then log normally:

```bash
source "${project_root}/vendor/bashlog.bash"

bashlog_info "Application started."
bashlog_warning 'Configuration file %s is deprecated' "${config_file}"
bashlog_error 'Request %s failed with status %s' "${request_id}" "${status}"
```

Routine log records go to standard error.  Standard output remains available for
application data, pipelines, and command substitution.

By default, bashlog adapts presentation only to whether standard error is a
terminal:

```text
stderr is a TTY      -> human rendering with severity styling
stderr is not a TTY  -> deterministic logfmt without ANSI
```

So an interactive call may look like:

```text
info: Application started.
```

while the same call under redirected or captured stderr becomes:

```text
level=info msg="Application started."
```

No container, init system, service manager, CI platform, or logging backend is
detected or guessed.

## Explicit Destinations and Deferred Queues

Logging still defaults to STDERR.  A call may explicitly select `STDOUT` or
a named in-memory queue:

```bash
bashlog_info --to STDOUT 'message for standard output'
bashlog_warning --to queue:errors 'warning: %s' "${reason}"
bashlog_error --to queue:errors 'request failed: %s' "${request_id}"

# Emit queued records FIFO, then clear this queue after success.
bashlog_queue_flush errors --to STDERR

# Alternatively, discard records without writing them:
bashlog_queue_clear errors
```

A destination must match `^(STDERR|STDOUT|queue:[A-Za-z0-9]+)$`.  Names
are case-sensitive, ASCII alphanumeric, and may not contain underscores,
dashes, or spaces.  Using `--to STDOUT` is an explicit choice to write log
records into the application's normally data-oriented stream.

Messages are timestamped, rendered, and, when `--context` is selected,
redacted and finally verified **when enqueued**.  The stored records are
replayed as unchanged text on flush, including their newlines; later rule
changes do not retroactively change the queue.  For `format=auto` and
`color=auto`, a queue observes the STDERR TTY state at enqueue time.
Direct `STDOUT` uses the STDOUT TTY state.

A failed flush returns `74` and preserves the **entire** queue.  If some
output was already written, a retry may duplicate it.  Queues have no size
limit, automatic flush, persistence, or library-managed exit traps: they
consume Bash-process memory until cleared, flushed, or process termination.
An empty or nonexistent queue is a successful no-op for flush and clear.

To move an entire queue into a caller variable without emitting it:

```bash
bashlog_error --to queue:errors 'request failed'
bashlog_queue_extract errors buffer
printf '%s' "$buffer"
```

Extraction assigns the complete, already-rendered text to an ordinary Bash
scalar, **preserving all trailing newlines**, then clears the queue.  An empty
or nonexistent queue produces an empty variable.  Unsafe variable identifiers,
readonly values, arrays, namerefs, integer scalars, exported variables, and
Bash special variables are rejected without consuming the queue.  Treat the
extracted bytes as caller-owned data; logging them again creates a new record.

A caller may also set the global default, or attach a default to an existing
active redaction context:

```bash
bashlog_destination_set --to queue:errors
bashlog_info 'queued using the global default'

bashlog_redaction_add secrets fixed 'private' '[REDACTED]'
bashlog_destination_set --context secrets --to STDERR
bashlog_error --context secrets 'value=%s' private

# Explicit --to overrides either default for one call:
bashlog_error --context secrets --to STDOUT 'safe message'

# Removing the context override restores inheritance of the global default:
bashlog_destination_reset --context secrets
bashlog_destination_get --context secrets
bashlog_destination_reset
```

The effective destination is selected in this order: explicit per-call
`--to`, selected context override, global default (initially `STDERR`).
Context routing does **not** implicitly enable redaction; a caller must
explicitly select the context on each protected logging call.  Destroying a
context removes its routing override, but does not clear queued records.
`bashlog_queue_flush` still defaults to immediate `STDERR` regardless of
configured defaults.

## Redaction in One Minute

Logging is a data-egress boundary.  bashlog does not guess which values are
sensitive, create a default redaction policy, or automatically apply registered
contexts.  Developers define the policy and explicitly invoke it.

Register a fixed secret in a context:

```bash
bashlog_redaction_add auth fixed \
  "${token}" \
  '[REDACTED TOKEN]'
```

Then either let the logging call apply that context:

```bash
bashlog_info --context auth \
  'Request failed with token=%s' \
  "${token}"
```

or redact a value directly and handle the result yourself:

```bash
if clean="$(bashlog_redact auth "${message}")"; then
  bashlog_info '%s' "${clean}"
fi
```

Both workflows are first-class public behavior.  A logging call without
`--context` performs no logger-managed redaction.

Use `--` when a format string could otherwise be mistaken for a bashlog option:

```bash
bashlog_info --context auth -- '-token=%s' "${token}"
```

## Design Boundaries

bashlog makes deliberately narrow, testable promises.

- **Sourcing is non-invasive.**  Loading bashlog does not install traps, change
  caller shell options, define generic logging functions, emit output, access the
  network, or take ownership of application control flow.
- **Runtime operation is pure Bash.**  Logging, formatting, timestamps, redaction,
  rendering, verification, and emission invoke no external commands.
- **Standard error is the default logging boundary.**  Explicit STDOUT output
  and caller-flushed in-memory queues are supported.  Downstream transport,
  persistence, and forwarding remain caller-managed.
- **Severity remains durable.**  Canonical severity names are present in both
  human and logfmt output.
- **Human styling is bounded.**  bashlog-owned color/intensity applies only to the
  severity signifier and resets immediately afterward.
- **Logfmt is ANSI-free.**  Machine-oriented output never receives bashlog-owned
  terminal styling.
- **Redaction is explicit.**  Registered contexts remain inert until the developer
  invokes one.
- **Selected redaction fails closed.**  Transformation and final verification
  suppress a protected record rather than emit a candidate that still matches an
  active rule.
- **Replacement text is literal.**  Replacement values never become shell code,
  ERE backreferences, glob syntax, or another secondary language.
- **The security-critical path remains readable.**  bashlog rejects `eval`,
  generated-code tricks, reversible obscurity, and fake encapsulation as security
  controls.

The project does **not** promise automatic secret discovery, secure memory or
zeroization, protection from caller-side `set -x`, protection from hostile code
already running in the same Bash interpreter, embedded-NUL support, Unicode
normalization, direct syslog/journald/network/file delivery, or automatic
host/container/service metadata.

The complete normative contract is in
[`doc/bashlog-spec.md`](doc/bashlog-spec.md).  The engineering posture behind the
contract is summarized in
[`doc/engineering-philosophy.md`](doc/engineering-philosophy.md), and the explicit
security analysis is maintained in [`doc/threat-model.md`](doc/threat-model.md).

## Runtime Requirements

- Bash 4.3 or newer.
- No external runtime commands required by bashlog itself.

Development and release tooling may use external programs.  That tooling is
outside the consumer runtime boundary.

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

bashlog_queue_flush
bashlog_queue_clear
bashlog_queue_extract

bashlog_destination_get
bashlog_destination_set
bashlog_destination_reset

bashlog_redaction_add
bashlog_redaction_context_destroy
bashlog_redact
```

Functions named `__bashlog_*` are implementation details and are not part of the
stable public API.

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

Threshold suppression returns success and avoids unnecessary message construction
and timestamp work.

## Presentation

The default presentation state is:

```text
format=auto
timestamp=off
color=auto
```

### Rendering

`bashlog_format_set` accepts:

```text
auto
human
logfmt
```

`auto` means exactly TTY-sensitive human/logfmt selection.  It does not mean
general environment detection.

### Tags

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

Tags use the explicitly ASCII grammar `[A-Za-z0-9_.:-]+` and preserve caller
order.  There is no ambient global-tag configuration.

### Timestamps

Timestamping is disabled by default.  Enable Bash-native UTC or local timestamps:

```bash
bashlog_timestamp_set utc
bashlog_timestamp_set local
```

UTC values have the form:

```text
2026-08-30T18:40:00Z
```

Local values include a numeric offset:

```text
2026-08-30T14:40:00-0400
```

bashlog does not invoke `date`.

### Color and Severity Styles

`bashlog_color_set` controls **whether** human severity styling is emitted:

```text
never
auto
always
```

The default is `auto`.

Per-level style controls **what** the severity signifier looks like when styling
is enabled.  The default palette is:

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

Override a level symbolically:

```bash
bashlog_level_style_set error magenta bold
bashlog_level_style_set warning blue normal
bashlog_level_style_set debug default normal
```

Supported foreground colors are:

```text
default black red green yellow blue magenta cyan white
```

Supported intensities are:

```text
normal bold dim
```

Inspect or reset style state:

```bash
bashlog_level_style_get critical
bashlog_level_style_reset error
bashlog_level_style_reset
```

Raw ANSI/SGR input is deliberately not accepted.  A style of `default normal`
emits no bashlog-owned style bytes for that severity.

## Redaction Contexts and Rules

Context names match the explicitly ASCII grammar:

```text
[A-Za-z_][A-Za-z0-9_.:-]*
```

Contexts follow a monotonic lifecycle:

```text
unseen -> active -> destroyed
```

The first successfully registered rule creates a context.  Active contexts are
append-only.  Destroyed context names cannot be reused during the same Bash
process.  Context destruction is not secure memory erasure.

Register rules with:

```text
bashlog_redaction_add CONTEXT MATCHER PATTERN REPLACEMENT
```

The matcher is exactly one of:

```text
fixed
glob
ere
```

Use `fixed` for known exact secrets whenever practical.  Glob and ERE are provided
for cases where pattern semantics are actually required.

Rules preserve registration order.  Duplicate matcher/pattern pairs are rejected,
patterns that can match empty input are rejected for glob/ERE, and replacement
text is always literal.

For logger-managed redaction, bashlog protects the fully formatted caller message
and each caller-supplied tag before rendering.  The completed rendered candidate
is then verified non-transformingly against the explicitly selected context
before immediate stream emission or insertion into a named queue.  Flushing
replays previously verified bytes without revisiting the context.

## Logfmt Contract

The deterministic field order is:

```text
[ts=TIMESTAMP] level=LEVEL [tag=TAG ...] msg=MESSAGE
```

`msg` is always double quoted.  The exact quoting and escaping contract, including
controls, backslashes, quotes, tabs, carriage returns, and newlines, is normative
in [`doc/bashlog-spec.md`](doc/bashlog-spec.md).

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

Builds produce three standalone sourceable artifacts and SHA-256 companions:

```text
dist/bashlog.dev.bash
dist/bashlog.dev.bash.sha256
dist/bashlog.bash
dist/bashlog.bash.sha256
dist/bashlog.min.bash
dist/bashlog.min.bash.sha256
```

- `bashlog.dev.bash` retains maintained Doxygen documentation;
- `bashlog.bash` is the ordinary readable consumer artifact; and
- `bashlog.min.bash` is the minified consumer representation.

All three must satisfy the same public behavior contract and remain usable without
repository `vendor/` state.

The expected project-family consumption model is a pinned standalone artifact,
commonly materialized by
[`wesley-dean/bashdeps`](https://github.com/wesley-dean/bashdeps) before runtime.

## Testing

`make test` runs the same Bats behavior/security suite against all three artifact
flavors.  CI additionally executes a representative compatibility contract under
Bash 4.3.

Security tests use negative assertions as well as positive ones.  An expected
replacement appearing is not sufficient evidence if protected input leaked
through another observable bashlog path.

See [`doc/testing.md`](doc/testing.md) and
[`tests/contract/README.md`](tests/contract/README.md).

## Dependabot Maintenance

Routine GitHub Actions version updates are checked weekly with a seven-day
cooldown and collected in the `actions-version-updates` group, including
eligible major, minor, and patch releases.  Security updates are separate
and depend on the repository's security-update features being enabled.
The current non-major auto-merge condition remains in place; a mixed
group containing a major update is expected to require the normal
review path.

Review each dependency within a group, particularly actions that can write
to the repository or publish release artifacts.  CI checks must exercise
the relevant changed behavior before their success is treated as evidence.
This configuration does not retroactively consolidate open PRs, guarantee
one PR per week, or enforce CODEOWNER approval without branch protection.

See ADR-033 for the decision, tradeoffs, and rollout boundaries.

## Documentation and Architecture

bashlog treats documentation as part of the architecture:

- `README.md` provides public orientation and representative usage;
- `doc/engineering-philosophy.md` collects reusable design principles such as
  developer agency, UNIX-style composition, explicit contracts, bounded promises,
  dependency skepticism, and readable/auditable implementation;
- `doc/bashlog-spec.md` defines normative observable behavior;
- `doc/decisions.md` is the concise architectural decision map;
- `doc/adr/*.md` preserves durable reasoning, alternatives, boundaries, and
  consequences;
- `doc/threat-model.md` consolidates assets, trusted computing base, trust
  boundaries, threats, mitigations, evidence, residual risk, and review triggers;
- `AGENTS.md` is the contributor-oriented operational map;
- maintained Doxygen comments document implementation contracts beside source;
- Bats tests provide executable evidence for observable guarantees.

`doc/decisions.md` is the maintained ADR navigation surface in the repository.
After dependencies are prepared, `make adr-index` generates the complete linked
ADR index at ignored `doc/adr/README.md`; Doxygen uses that ephemeral page as the
published site's main page.

Generated Doxygen reference output lives under `doc/reference/` and is not
committed.

## Support, Security, and Contributions

- See [`SUPPORT.md`](SUPPORT.md) for ordinary support and bug-report guidance.
- See [`SECURITY.md`](SECURITY.md) for private vulnerability reporting.
- See [`CONTRIBUTING.md`](CONTRIBUTING.md) for contribution expectations.
- See [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) for collaboration expectations.

## License

bashlog is dedicated to the public domain under CC0 1.0 Universal.  See
[`LICENSE`](LICENSE).

## Shared Coding Standards

This repository adopts the complete pinned `coding_standards@v2.1.0` snapshot under `doc/standards/`; `.codingstandardrc` records its verified release digest.  Applicable imported standards are governing requirements unless an accepted local ADR or explicit policy refines them.  Presence does not imply applicability, examples remain illustrative, imported standards are not edited locally, and upgrades are reviewed repository changes rather than automatic synchronization.

Authoritative shared documentation standards used here:

- Bash: `doc/standards/bash/documentation-standard.md`

