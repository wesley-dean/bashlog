# bashlog

`bashlog` is a small, sourceable Bash logging library with explicit severity,
formatting, presentation, and opt-in redaction controls.  It is designed to be
embedded into shell tooling without taking over application policy or runtime
control flow.

The project prioritizes explicit contracts, readable implementation, developer
agency, Bash 4.3 portability, and bounded security claims.  Consumer runtime uses
Bash language facilities and builtins only; repository tooling may use explicit,
pinned development dependencies.

## Quick Start

Source one generated artifact:

```bash
source ./dist/bashlog.bash
```

Log through a canonical severity helper:

```bash
bashlog_info 'processed %s records' "${count}"
bashlog_warning --tag cache 'cache miss for %s' "${key}"
```

By default, the active threshold is `info`.  Records less severe than the
threshold are suppressed.

Configure the threshold explicitly:

```bash
bashlog_level_set debug
```

Select output format explicitly when needed:

```bash
bashlog_format_set human
bashlog_format_set logfmt
bashlog_format_set auto
```

`auto` chooses human output when standard error is a TTY and deterministic logfmt
otherwise.

Protect explicitly selected values through a named redaction context:

```bash
bashlog_redaction_add api fixed "${API_TOKEN}" '[REDACTED]'
bashlog_info --context api 'calling upstream with token=%s' "${API_TOKEN}"
```

bashlog does not guess which values are sensitive.  Once a valid context is
explicitly selected, however, redaction failure is fail-closed for that
bashlog-controlled operation.

## Project Scope

bashlog is intentionally a library rather than a command dispatcher, service,
transport, log collector, storage layer, configuration framework, or secret
manager.

Sourcing bashlog does not intentionally:

- change shell options;
- install traps;
- create generic aliases or convenience functions;
- access the network;
- mutate the filesystem;
- execute external commands;
- discover deployment infrastructure;
- infer which values are sensitive; or
- perform runtime plugin discovery.

The caller owns application policy, data acquisition, transport, persistence,
retention, and downstream access control.

## Public API

The supported public functions are:

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

Names beginning `__bashlog_` are implementation details and are not public
compatibility commitments.

The accepted normative behavior, including return statuses and exact output
semantics, is defined in [`doc/bashlog-spec.md`](doc/bashlog-spec.md).

## Severity Model

bashlog uses the conventional eight-level syslog severity ordering:

| Severity | Numeric value |
| --- | ---: |
| `emergency` | 0 |
| `alert` | 1 |
| `critical` | 2 |
| `error` | 3 |
| `warning` | 4 |
| `notice` | 5 |
| `info` | 6 |
| `debug` | 7 |

A message is emitted when its severity is at least as severe as the configured
threshold.

For example:

```bash
bashlog_level_set warning

bashlog_info 'not emitted'
bashlog_warning 'emitted'
bashlog_error 'emitted'
```

## Generic Logging

`bashlog_log` accepts a level followed by the same logging options and printf-style
message interface used by the severity helpers:

```bash
bashlog_log notice 'starting %s' "${job_name}"
bashlog_log 3 --tag database 'query failed: %s' "${reason}"
```

The canonical helper functions are thin public entry points into the same logging
pipeline.

## Presentation

### Format

The format mode is one of:

```text
auto
human
logfmt
```

Configure it with:

```bash
bashlog_format_set auto
```

`human` is intended for direct terminal reading.  `logfmt` is deterministic,
machine-oriented text.  `auto` selects between them according to whether standard
error is attached to a TTY.

Standard error is always the log sink.  Format selection changes representation,
not transport.

### Timestamps

Timestamp mode is one of:

```text
off
utc
local
```

For example:

```bash
bashlog_timestamp_set utc
```

Timestamps are off by default.

### Tags

Tags are explicit per-call metadata:

```bash
bashlog_info --tag worker --tag sync 'processed %s items' "${count}"
```

Tag values use the deliberately narrow grammar documented in the specification.
Tags are not inferred from environment, process name, deployment platform, or
other ambient context.

### Color

Color policy is one of:

```text
never
auto
always
```

Configure it with:

```bash
bashlog_color_set auto
```

bashlog-owned ANSI styling is emitted only by the human renderer and only around
the canonical severity token.  Logfmt never contains bashlog-owned ANSI styling.

The default severity styles are:

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
before standard-error emission.

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

The ADR landing page at [`doc/adr/README.md`](doc/adr/README.md) is generated and
committed so GitHub can present it directly when browsing the ADR directory.
`make adr-index` regenerates it from the ADR corpus using the pinned adrctl
documentation dependency plus maintained intro/outro fragments.  `make docs`
regenerates the ADR index and also produces Doxygen reference output.

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
