# ADR-026: Adaptive Human/Logfmt Rendering and Environment-Agnostic Stderr Transport

Date: 2026-08-30

## Status

Proposed

## Intent and Documentation Posture

This Architecture Decision Record defines how bashlog should render records when
the application developer does not know, and often cannot know, whether the same
script will eventually run interactively, from cron, as a systemd service, inside
a Docker or Podman container, under an orchestrator, in CI, or with standard
error redirected to another consumer.

The decision deliberately separates three concerns that are frequently conflated:

1. severity is semantic state used for threshold filtering;
2. rendering determines how that state and message data are represented as text;
3. the environment attached to file descriptor 2 owns transport, persistence,
   forwarding, and aggregation after bashlog writes the record.

The goal is not to make bashlog environment-aware.  The goal is to let bashlog
adapt only to a property Bash can directly and reliably observe without external
commands: whether standard error is currently a terminal.

## Context

The first implemented bashlog contract has one intentionally narrow sink:
standard error.  Every severity is written there so standard output remains the
application's data channel.  This works naturally in a wide range of deployment
environments:

- a terminal displays standard error to a human;
- systemd normally captures a service's standard error and places it into the
  journal;
- Docker and Podman capture container standard output and standard error and hand
  those streams to their configured logging drivers;
- cron, CI systems, supervisors, and orchestration platforms may capture or
  redirect the streams according to their own policy;
- ordinary shell redirection can send standard error to a file, pipe, or other
  consumer.

A sourceable logging library cannot reliably infer all of those environments.
Detection based on operating-system names, container environment variables,
process ancestry, systemd-specific variables, filesystem probes, or external
commands would expand the runtime boundary and would still be incomplete.  The
same script may also move between those environments without source changes.

The project therefore should not require application developers to predict their
future deployment environment in order to select a logging transport.

At the same time, the audience for a log line does differ materially depending on
whether standard error is a terminal.  Human-facing terminal output benefits from
compact punctuation and optional severity color.  Non-terminal output is more
likely to be persisted, parsed, searched, shipped, or consumed by another system.
A deterministic key/value representation is more useful there.

The project considered syslog framing and direct syslog transport while exploring
this problem.  Local systemd journal integration can already occur through the
normal standard-error stream.  Docker and Podman likewise already own container
log transport.  Direct UDP or TCP syslog would create a distinct network sink and
a dependency on a reachable compatible receiver, even though it would not
necessarily depend on rsyslog itself.  That is a materially different boundary
from writing to standard error and is not required to solve the current problem.

## Decision Drivers

- Application developers should not need to know whether deployment will be bare
  metal, a container, a terminal, a service, CI, cron, or another environment.
- Standard error should remain the universal bashlog sink.
- bashlog should not attempt to detect Docker, Podman, systemd, journald, OpenRC,
  BusyBox, Kubernetes, Swarm, or other execution infrastructure.
- Automatic behavior should depend only on directly observable Bash state rather
  than heuristics about the environment.
- Human-facing output should remain pleasant to read.
- Non-terminal output should preserve severity and other fields in a form that is
  straightforward for machines to parse.
- Severity filtering must remain independent of whether the severity name is
  visually decorated.
- The textual record should preserve severity after it leaves bashlog so that
  downstream systems and later readers do not lose the classification.
- The new renderer must not weaken the accepted redaction boundary.
- Runtime behavior must remain pure Bash and compatible with the accepted Bash
  floor unless a separate ADR intentionally changes that floor.
- The format choice should remain explicitly overrideable for callers with a
  known integration requirement.

## Decision

bashlog SHALL continue to use standard error as its normal and universal logging
sink.

bashlog SHALL add a rendering mode with the public configuration interface:

```text
bashlog_format_get
bashlog_format_set MODE
```

`MODE` SHALL be exactly one of:

```text
auto
human
logfmt
```

The default SHALL be `auto`.

### `auto` Rendering

`auto` SHALL be defined narrowly and completely as:

```text
stderr is a TTY      -> human
stderr is not a TTY  -> logfmt
```

Terminal state SHALL be evaluated through Bash's `[[ -t 2 ]]` facility.  bashlog
SHALL NOT invoke `tty`, `test`, `stat`, `ps`, `systemctl`, `docker`, `podman`, or
another external command to choose a renderer.

The decision SHALL be made for the logging operation rather than once at source
time.  Ordinary shell redirection therefore remains meaningful.  The same script
may produce human output when run directly and logfmt output when the caller
redirects standard error.

`auto` SHALL NOT inspect:

- operating-system identity;
- init-system identity;
- container markers;
- cgroup state;
- process ancestry;
- `JOURNAL_STREAM` or other service-manager variables;
- Docker, Podman, Kubernetes, or Swarm metadata;
- network configuration;
- or filesystem state.

The word `auto` means only terminal-sensitive renderer selection.  It is not a
general environment-detection mode.

### Explicit Rendering Modes

`human` SHALL always select the human renderer regardless of whether standard
error is currently a terminal.

`logfmt` SHALL always select the logfmt renderer regardless of whether standard
error is currently a terminal.

An invalid mode SHALL return public usage status `64`, emit no caller message,
and leave the previous format mode unchanged.

### Severity Semantics Remain Independent

Log severity SHALL remain semantic state used for threshold filtering before
rendering.

The existing relationship remains:

```text
message severity <= active threshold
```

Changing the renderer SHALL NOT change whether a message is eligible for
emission.  A warning remains a warning whether its output is human text or
logfmt.  A threshold-suppressed message remains suppressed regardless of the
selected renderer.

The canonical severity SHALL remain present in every emitted renderer.  bashlog
SHALL NOT use terminal color as a substitute for durable severity information.
The textual classification must survive redirection, capture, copying, storage,
and later inspection.

### Human Renderer

The human renderer SHALL remain compact and human-oriented.  ADR-025 defines its
optional timestamps, tags, and color behavior.

Representative forms are:

```text
info: application started
warning [database]: connection delayed
[2026-08-30T18:40:00Z] error [api]: request failed
```

The canonical lowercase severity name is retained.

### Logfmt Renderer

The non-terminal machine-oriented renderer SHALL use a deliberately constrained
logfmt profile.

logfmt is an established key/value log convention but is not a formally
standardized protocol.  bashlog SHALL therefore document its exact profile
rather than claiming conformance to a nonexistent formal standard.

The initial field order SHALL be deterministic:

```text
[ts=TIMESTAMP] level=LEVEL [tag=TAG ...] msg=MESSAGE
```

where:

- `ts` appears only when timestamping is enabled;
- `level` always appears and contains the canonical lowercase severity;
- zero or more `tag` fields appear in the exact order supplied to the logging
  call;
- `msg` always appears and contains the formatted message.

Examples:

```text
level=info msg="application started"
level=warning tag=database msg="connection delayed"
ts=2026-08-30T18:40:00Z level=error tag=api msg="request failed"
```

The specification adopted with this ADR SHALL define exact quoting and escaping
rules for every representable Bash string accepted as message data.  At minimum,
spaces, quotes, backslashes, tabs, carriage returns, newlines, empty strings, and
other supported control bytes require deterministic behavior.

The implementation SHALL NOT call the result logfmt-compatible until fixture
tests demonstrate that representative lines are accepted by established logfmt
parsers.

Repeated `tag` keys are intentional.  Their occurrence order preserves the
caller's tag ordering without inventing an array syntax that logfmt does not
standardize.

### Color and Renderer Interaction

Color is a human-presentation feature, not structured log data.

The logfmt renderer SHALL NEVER emit bashlog-owned ANSI color sequences,
regardless of whether standard error happens to be a terminal and regardless of
whether the configured color preference is `auto` or `always`.

The color modes defined by ADR-025 therefore control the human renderer only.
Within the human renderer:

- `never` emits no bashlog-owned ANSI color;
- `auto` uses color only when standard error is a terminal;
- `always` requests color even when human output is redirected.

This means the default combination:

```text
format=auto
color=auto
```

behaves as follows:

```text
interactive terminal  -> human + color
non-terminal stderr    -> logfmt + no color
```

### Timestamps and Tags Across Renderers

Timestamps and tags are semantic presentation fields shared by both renderers.
ADR-025 defines how callers configure them.

The same logical values SHALL be represented according to the selected renderer:

```text
human:
[2026-08-30T18:40:00Z] warning [database]: connection delayed

logfmt:
ts=2026-08-30T18:40:00Z level=warning tag=database msg="connection delayed"
```

Timestamping remains disabled by default.  Tags remain explicit per-call data.

### Redaction and Serialization

Renderer selection and serialization SHALL NOT weaken a registered redaction
policy.

This requirement is especially important for logfmt because quoting and escaping
are reversible transformations.  A protected value containing a quote, backslash,
newline, tab, or other encoded character is not considered protected merely
because serialization inserts escape characters and the original byte sequence
no longer appears literally in the final line.

The implementation and normative public specification SHALL define a bounded,
auditable ordering that satisfies all of the following:

1. caller-controlled semantic message and tag data are subject to the selected
   redaction context before renderer encoding can disguise a match;
2. renderer encoding operates only on data that has satisfied the required
   security transformation;
3. the final emitted bytes remain subject to an appropriate non-transforming
   verification step before crossing the sink boundary;
4. no renderer-specific escape mechanism is treated as a substitute for
   redaction;
5. redaction failure remains fail-closed and suppresses the protected record.

The exact implementation ordering requires feasibility tests before this ADR is
ratified as implemented behavior.  The project SHALL prefer a slightly more
verbose but directly auditable pipeline over clever encoding-aware matcher
machinery.

If preserving the existing complete-rendered-candidate semantics and supporting a
safe logfmt encoder conflict, the conflict SHALL be resolved explicitly in the
specification and, if necessary, by an ADR that supersedes the affected portion
of ADR-017 or ADR-024.  Implementation SHALL NOT silently weaken either contract.

### System Logging and Environment Ownership

bashlog SHALL NOT automatically switch to a platform-specific system logger.

In particular, normal operation SHALL NOT:

- invoke the external `logger` command;
- open a syslog UDP or TCP connection;
- attempt to open a journald Unix-domain socket;
- prepend systemd priority framing merely because the host appears to use
  systemd;
- detect or configure rsyslog or syslog-ng;
- detect Docker or Podman logging drivers;
- or choose a sink based on guessed deployment infrastructure.

When bashlog runs as a systemd service, the environment may capture standard
error into the journal.  When bashlog runs in a container, Docker, Podman, or an
orchestrator may capture standard error and route it according to runtime policy.
Those are downstream environment responsibilities and require no special bashlog
transport.

Direct remote syslog remains a possible future feature.  If added, it SHALL be an
explicitly configured transport governed by a separate ADR because it introduces
a network sink and a dependency on a reachable compatible receiver.  Such a
transport would not inherently require rsyslog specifically, but it would expand
the runtime and failure boundary beyond the universal standard-error sink.

## Promises

1. **One universal default sink.**  Normal bashlog logging continues to write to
   standard error regardless of deployment environment.

2. **No deployment prediction required.**  Application developers do not need to
   know whether the script will run interactively, as a service, in a container,
   in CI, or under another supervisor in order to obtain useful default output.

3. **Narrow automatic behavior.**  `auto` depends only on `[[ -t 2 ]]` and does
   not infer a container, operating system, init system, or logging platform.

4. **Durable severity.**  Every emitted renderer preserves the canonical severity
   in textual form even though threshold filtering occurs independently of
   rendering.

5. **Machine-oriented non-terminal output.**  The default non-terminal renderer
   is deterministic logfmt rather than terminal-oriented punctuation or ANSI
   presentation.

6. **No ANSI in logfmt.**  bashlog-owned color never appears in the logfmt
   renderer.

7. **No new external runtime dependency.**  Renderer selection, rendering, and
   emission remain implementable with Bash facilities only.

8. **No implicit syslog dependency.**  The default design requires neither
   rsyslog nor syslog-ng nor an open syslog port.

9. **Redirection remains meaningful.**  `./script` and `./script 2>run.log` may
   intentionally choose different textual renderers under `format=auto` because
   the consumer attached to standard error changed.

10. **Serialization is not redaction.**  Reversible logfmt escaping cannot satisfy
    a redaction obligation by itself.

## Non-Promises

1. `auto` does not promise to identify the ultimate human or machine consumer
   correctly.  It makes one documented distinction: TTY versus non-TTY.

2. A non-terminal is not necessarily a machine parser, and a terminal is not
   necessarily viewed by a human.  Explicit `human` and `logfmt` modes exist for
   callers that know otherwise.

3. bashlog does not promise that Docker, Podman, journald, CI, or another consumer
   will preserve, parse, index, rotate, or forward logs in a particular way.
   Those behaviors belong to the downstream environment.

4. The presence of logfmt fields does not create a structured transport protocol.
   The line is still textual data written to standard error.

5. bashlog does not promise syslog facility metadata, journald native fields,
   container labels, hostnames, process IDs, service-unit names, or orchestration
   metadata in this tranche.

6. bashlog does not promise direct network log delivery or delivery
   acknowledgment.

7. logfmt itself is not represented as a formally standardized format.  bashlog
   promises only the exact profile documented by its own specification.

8. `format=auto` does not promise byte-identical output when the same logging call
   is run under different file-descriptor conditions.  Environment-sensitive
   representation is the purpose of that mode.

## Adversary and Failure Model

This decision accounts for:

- a developer who writes the application without knowing its final deployment
  environment;
- the same script moving from a terminal to systemd, Docker, Podman, cron, CI, or
  an orchestrator without source changes;
- standard error being redirected for one invocation but not another;
- misleading environment variables that appear to identify systemd or a
  container but no longer describe the actual file descriptor;
- a logfmt message containing spaces, quotes, backslashes, tabs, newlines, or
  other characters requiring encoding;
- a sensitive registered value whose logfmt representation differs from its raw
  message representation;
- a downstream parser expecting deterministic field names and ordering;
- a caller explicitly forcing human output into a non-terminal or logfmt output
  onto a terminal;
- and a future maintainer tempted to add platform detection because one specific
  deployment environment would become more convenient.

The decision does not attempt to defend against a malicious downstream log
consumer.  Once a verified record crosses standard error, storage, retention,
forwarding, access control, and downstream parsing are outside bashlog's process
boundary.

## Operational Constraints

- Standard error MUST remain the normal logging sink.
- Format mode MUST be one of `auto`, `human`, or `logfmt`.
- Format mode MUST default to `auto`.
- `auto` MUST resolve only through `[[ -t 2 ]]`.
- TTY standard error under `auto` MUST select `human`.
- Non-TTY standard error under `auto` MUST select `logfmt`.
- The canonical severity MUST remain present in human and logfmt output.
- Severity threshold decisions MUST remain independent of renderer selection.
- Logfmt output MUST contain no bashlog-owned ANSI color sequences.
- Logfmt field order and escaping MUST be deterministic and normatively
  specified before implementation is accepted.
- Renderer encoding MUST NOT weaken registered redaction policy.
- bashlog MUST NOT infer Docker, Podman, systemd, journald, OpenRC, Kubernetes,
  Swarm, or another deployment environment for normal renderer selection.
- bashlog MUST NOT invoke `logger` or another external system-logging command.
- bashlog MUST NOT open an implicit TCP or UDP syslog sink.
- Invalid format configuration MUST fail atomically without changing prior state.
- A future direct syslog/network transport MUST require separate architectural
  review.

## Considered Alternatives

### Always Use Human Rendering

Keeping `level: message` everywhere would be maximally stable and visually
familiar.

It was not selected as the default because non-terminal output is frequently
persisted or machine-consumed.  A deterministic key/value representation
preserves severity and tags in a form that downstream tools can parse without
reverse-engineering punctuation.

### Always Use Logfmt

Using logfmt everywhere would produce one stable representation and simplify
machine processing.

It was rejected as the default because interactive shell users benefit from a
more compact human-oriented form and severity-aware color.  bashlog is intended
to remain pleasant as a Bash developer tool, not only as a log serialization
library.

### Require the Caller to Select a Format

This would make behavior entirely explicit and eliminate environment-sensitive
rendering.

It was rejected as the default because the application developer often does not
know the eventual deployment environment.  Requiring a source-level decision
would push deployment knowledge into application code and encourage wrappers or
environment probes outside bashlog.

Explicit overrides remain available for integrations that do know their
requirement.

### Detect systemd, Docker, Podman, or Containers

Environment detection could theoretically select specialized framing or sinks.

It was rejected because those signals are incomplete, mutable, and often require
filesystem/process inspection or external commands.  More importantly, bashlog
does not need to identify the platform when standard error already provides the
correct composition boundary.

### Automatically Use systemd Priority Prefixes

systemd can interpret severity prefixes on service output, which could preserve
native journal priority without invoking `logger`.

It was rejected as a universal default because the same bytes are ordinary
message text when the consumer is Docker, Podman, a file, a terminal, or another
non-systemd reader.  Correctly proving that file descriptor 2 currently targets
the journal is more complicated than checking an environment variable and would
pull bashlog toward platform detection.

### Direct UDP/TCP Syslog

Bash can support network redirections on installations built with the relevant
feature, which makes process-free syslog transmission technically possible.

It was deferred because it creates a second sink, network behavior, delivery and
failure semantics, protocol-format questions, and a dependency on a reachable
receiver.  It solves a different problem from portable local logging.  If a real
remote-syslog use case appears, it deserves a separate ADR.

### Use RFC 5424 as the Normal Stderr Format

RFC 5424 provides a formal syslog message structure with severity/facility,
timestamps, host identity, application identity, process metadata, message IDs,
and structured data.

It was rejected for ordinary stderr because bashlog would need to manufacture or
acquire fields that are intentionally outside its present responsibility.  RFC
5424 is more appropriate if the project later implements an actual syslog
transport.

### Omit Severity from Human Output

Severity filtering does not technically require printing the severity token, so
human output could be visually cleaner without it.

It was rejected because once the record leaves bashlog, the classification would
be irrecoverable from plain text.  Textual severity is useful for humans,
searching, support bundles, downstream parsing, and historical analysis.  Color
is enhancement, not durable metadata.

### Use JSON Lines Instead of Logfmt

JSON Lines is widely machine-readable and has stronger formal syntax than
logfmt.

It was deferred rather than rejected permanently.  Correct JSON string encoding
and the resulting visual weight are larger concerns for a small pure-Bash
library.  Logfmt offers a better human/machine compromise for the current scope.
A later structured-output ADR may revisit JSON if actual consumers require it.

## Consequences

The default behavior becomes intentionally adaptive.  Running a script directly
in a terminal and redirecting its standard error may produce different textual
representations while preserving the same severity, message meaning, tags,
timestamp policy, redaction policy, and sink.

This behavior is easy to explain because it depends on one observable fact rather
than a hierarchy of environment heuristics.

The logfmt renderer adds meaningful implementation and testing work.  Escaping is
not cosmetic: it must be deterministic, parser-compatible, and integrated with
the redaction security boundary.  That work should be completed with the same
red-phase test posture used for the original redaction engine.

The architecture avoids a larger cost: bashlog does not become a platform-
detection or log-transport framework.  systemd, Docker, Podman, orchestration
systems, and shell redirection continue to do what they already do well with
standard error.

## Source Lineage

This decision extends:

- ADR-013's narrow library/caller responsibility boundary;
- ADR-014's pure-Bash runtime and explicit external-command boundary;
- ADR-017's common logging pipeline and standard-error emission model;
- ADR-018's redaction security obligation;
- ADR-019's requirement that critical behavior remain directly auditable;
- ADR-024's fail-closed final output boundary;
- and ADR-025's timestamp, tag, and human-color presentation decisions.

The logfmt choice follows established logfmt prior art while explicitly
acknowledging that logfmt has not been formally standardized.  bashlog therefore
owns the exact syntax it promises rather than outsourcing correctness to an
informal name.

## Open Questions and Follow-Ups

- Feasibility tests must establish the exact pure-Bash quoting and escaping
  algorithm for the bashlog logfmt profile on Bash 4.3.
- Compatibility fixtures should be parsed by one or more established logfmt
  implementations before the specification calls the renderer compatible.
- The redaction pipeline must be designed and tested so reversible renderer
  encoding cannot conceal an unredacted registered value.
- The public specification must define exact behavior for embedded newlines and
  other representable control characters under logfmt.
- The exact ANSI severity palette for the human renderer remains a separate
  specification detail under ADR-025.
- Direct remote syslog remains deferred until a concrete requirement justifies a
  network sink and its delivery semantics.
- JSON Lines remains a possible future structured renderer if concrete consumers
  require stronger standardized serialization.

## Related Decisions

- ADR-002: Bash Runtime and Portability Baseline
- ADR-013: Sourceable Library Scope and Responsibility Boundary
- ADR-014: Pure Bash Runtime and External Command Boundary
- ADR-015: Namespaced Public API and Caller-Owned Convenience Wrappers
- ADR-017: Logging Pipeline, Levels, Formatting, and Emission
- ADR-018: Redaction as an Opt-In Security Boundary
- ADR-019: Readability, Auditability, and Rejection of Obscurity
- ADR-024: Final Redaction Verification and Fail-Closed Output Boundary
- ADR-025: Optional Presentation Metadata, Tags, and Color
