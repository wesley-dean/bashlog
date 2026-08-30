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

The decision deliberately separates four concerns that are frequently conflated:

1. severity is semantic state used for threshold filtering;
2. explicitly selected redaction protects caller-supplied semantic data before
   presentation encoding;
3. rendering determines how semantic fields are represented as text;
4. the environment attached to file descriptor 2 owns transport, persistence,
   forwarding, and aggregation after bashlog writes the record.

The goal is not to make bashlog environment-aware.  The goal is to let bashlog
adapt only to a property Bash can directly and reliably observe without external
commands: whether standard error is currently a terminal.

The ordering is equally important.  Human punctuation, logfmt quoting and
escaping, and ANSI color are renderer concerns.  When the developer explicitly
selects a redaction context for a logging call, that context is applied to
caller-supplied semantic data before rendering begins.  A renderer therefore
never becomes the mechanism by which a secret is located or removed.

This ADR does not change ADR-018's opt-in security model.  bashlog provides
redaction capability; it does not decide that a logging call requires redaction.
The developer retains responsibility for deciding what is sensitive, registering
the appropriate rules, and explicitly selecting a context when logging.  Once a
context is explicitly selected, bashlog assumes the corresponding fail-closed
security obligation.

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

The introduction of more than one renderer also exposes a boundary that was less
visible in the first implementation.  The current logger formats a complete
human line and then applies redaction to that rendered string when the caller
explicitly selects a context.  That is workable while only one renderer exists.
Once human and logfmt renderers coexist, making redaction depend on presentation
syntax would force the redaction engine to understand quoting, escaping,
delimiters, and every future renderer.

That is the wrong dependency direction.  The application supplies semantic data.
If the developer explicitly requests redaction for the call, bashlog protects
that semantic data.  A renderer then serializes the resulting values.  For
example, if the application message contains a registered value:

```text
password=foo"bar
```

and the developer logs with the applicable context, redaction first produces a
protected semantic message such as:

```text
password=[REDACTED]
```

Only afterward may the logfmt renderer quote or escape that already-protected
message:

```text
level=info msg="password=[REDACTED]"
```

The renderer never receives `foo"bar` as data that still requires discovery.

If the developer does not select a redaction context, bashlog does not perform
this transformation automatically.  Existing contexts are not ambient policy,
and bashlog does not apply every registered context merely because one or more
contexts exist.  That behavior is deliberate: the developer owns the decision to
invoke the redaction facility.

The project also considered syslog framing and direct syslog transport while
exploring this problem.  Local systemd journal integration can already occur
through the normal standard-error stream.  Docker and Podman likewise already own
container log transport.  Direct UDP or TCP syslog would create a distinct
network sink and a dependency on a reachable compatible receiver, even though it
would not necessarily depend on rsyslog itself.  That is a materially different
boundary from writing to standard error and is not required to solve the current
problem.

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
- Severity filtering must remain independent of rendering.
- The textual record should preserve severity after it leaves bashlog so that
  downstream systems and later readers do not lose the classification.
- Redaction must remain explicitly developer-selected rather than becoming
  automatic application policy.
- bashlog should provide strong mechanisms without assuming that it knows the
  application's sensitivity model better than the developer.
- Primary redaction should operate on semantic caller data, not renderer-specific
  encoded text.
- Rendering and escaping should never need to understand how secrets were found.
- Final verification should remain a fail-closed defense immediately before the
  sink boundary when a context has been explicitly selected.
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

The decision SHALL be made for each logging operation rather than once at source
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
message construction, redaction, or rendering.

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

### Redaction Remains Explicit and Developer-Owned

This ADR SHALL preserve ADR-018's opt-in redaction boundary and the initial public
logging contract's explicit `--context CONTEXT` selection model.

bashlog SHALL NOT:

- infer from message contents that redaction should occur;
- infer which values are sensitive;
- automatically select a registered context;
- maintain an ambient current logging context;
- apply every active context to every logging call;
- or silently enable redaction because one or more rules have been registered.

Registering rules creates a capability that the developer may invoke.  It does
not create implicit policy for unrelated logging calls.

A logging call that does not explicitly select a redaction context SHALL proceed
without bashlog redaction transformation or redaction final verification.  That
record is intentionally unredacted by bashlog.

A logging call that explicitly selects a context SHALL validate that context
according to the accepted contract and SHALL enter the fail-closed redaction path
defined by ADR-018 and related decisions.

This division of responsibility is intentional.  The developer knows the
application's data model, sensitivity requirements, performance needs, and
logging purpose.  bashlog supplies an auditable mechanism and strong behavior
once that mechanism is explicitly invoked; it does not substitute its own policy
judgment for the developer's.

### Logical Record and Security Ordering

For an eligible logging call, bashlog SHALL treat the record as semantic fields
before it treats the record as serialized text.

The logical record contains, as applicable:

```text
severity
formatted message
zero or more tags
optional timestamp
```

The processing order SHALL be conceptually:

```text
validate call and explicitly requested context, if any
    -> severity/threshold decision
    -> printf-style message construction
    -> acquire optional Bash-native timestamp
    -> assemble logical fields
    -> if a context was explicitly selected:
         transform and verify caller-supplied message and tags
    -> choose renderer
    -> serialize fields as human or logfmt text
    -> add renderer-owned presentation decoration, if any
    -> if a context was explicitly selected:
         perform final non-transforming verification
    -> emit to standard error
```

Primary redaction occurs only when the developer explicitly selects a context.
When selected, it occurs before renderer-specific quoting, escaping, punctuation,
or ANSI decoration.

The caller-supplied fields subject to the selected redaction context SHALL be:

- the fully formatted message; and
- every caller-supplied tag, in argument order.

Canonical severity and a bashlog-generated timestamp are library-owned metadata.
They SHALL NOT be transformed by the primary redaction pass merely because they
later appear in the same emitted line.  When a context is selected, they remain
part of the final output candidate and are therefore subject to final
non-transforming verification as described below.

Each caller-supplied field SHALL be transformed independently using the explicitly
selected context's accepted rule order and existing matcher semantics.  A failure
to transform or verify any protected field SHALL fail closed for the entire
logging operation.  bashlog SHALL NOT emit a partially protected record.

This field boundary is intentional.  A redaction pattern protects application
data, not punctuation introduced later by a renderer.  A pattern is not promised
to span multiple logical fields or to depend on the exact delimiters that one
renderer places between fields.

The public `bashlog_redact` operation remains an explicitly invoked transform-only
API over the exact string supplied by its caller.  This ADR changes how the
logging pipeline uses a context when the developer selects one; it does not
change the standalone transform API's meaning or make that API automatic.

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

Human punctuation is presentation syntax.  When redaction is selected, that
syntax is created only after caller data has passed the primary redaction stage.

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
- `msg` always appears and contains the formatted message, redacted first only
  when the developer explicitly selected a context.

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

When a context is selected, quoting and escaping SHALL occur only after the
semantic field being encoded has satisfied the primary redaction stage.  The
serializer therefore does not need to locate protected values inside escaped text
and SHALL NOT contain a second, renderer-specific redaction language.

When no context is selected, the serializer encodes the caller's semantic data as
provided; it does not opportunistically redact values during serialization.

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

When a context is selected, ANSI decoration SHALL be added after primary
redaction.  Color bytes therefore cannot prevent a caller-supplied secret from
being found by the redaction engine.

### Timestamps and Tags Across Renderers

Timestamps and tags are logical fields shared by both renderers.  ADR-025 defines
how callers configure them.

The same logical values SHALL be represented according to the selected renderer:

```text
human:
[2026-08-30T18:40:00Z] warning [database]: connection delayed

logfmt:
ts=2026-08-30T18:40:00Z level=warning tag=database msg="connection delayed"
```

Timestamping remains disabled by default.  Tags remain explicit per-call data.
When a context is selected, tags are protected before either renderer serializes
them.  When no context is selected, tags are rendered as supplied after normal
tag validation.

### Final Verification After Rendering

ADR-024 established the useful invariant that bytes governed by an explicitly
selected redaction context must not cross the sink boundary when verification
cannot be completed safely.  This ADR retains that fail-closed defense while
moving primary transformation earlier in the pipeline.

When and only when a logging call explicitly selects a redaction context, bashlog
SHALL perform a final non-transforming verification after human/logfmt
serialization and any human-only color decoration are complete.

This final step is defense in depth.  It is not where primary redaction occurs,
and the renderer SHALL NOT rely on final verification to repair unredacted caller
data.

If renderer-owned syntax or encoding happens to create a byte sequence matching
an active rule in the selected context, final verification MAY suppress the
record even though all caller-supplied semantic fields were already transformed
successfully.  Such a false-positive suppression is preferable to weakening the
existing fail-closed sink invariant.  The implementation SHALL NOT respond by
iteratively rewriting renderer output until verification passes.

When no redaction context is explicitly selected, no redaction verification is
performed.  bashlog does not inspect the record against unrelated registered
contexts merely because they exist.

If experience demonstrates that verifying encoded bytes against semantic rules
creates unacceptable false positives, that behavior must be reconsidered through
an explicit ADR rather than by weakening final verification silently.

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

4. **Developer-owned redaction choice.**  bashlog never silently decides that a
   logging call should be redacted.  Registration creates an available mechanism;
   explicit context selection activates it for a logging call.

5. **Durable severity.**  Every emitted renderer preserves the canonical severity
   in textual form even though threshold filtering occurs independently of
   rendering.

6. **Redaction precedes presentation encoding when selected.**  Caller-supplied
   message and tag values are transformed and verified before human punctuation,
   logfmt quoting and escaping, or ANSI decoration are introduced.

7. **Renderer independence.**  Human and logfmt serialization do not need their
   own secret-matching semantics because explicit redaction, when requested,
   occurs before rendering.

8. **Machine-oriented non-terminal output.**  The default non-terminal renderer
   is deterministic logfmt rather than terminal-oriented punctuation or ANSI
   presentation.

9. **No ANSI in logfmt.**  bashlog-owned color never appears in the logfmt
   renderer.

10. **Final fail-closed verification remains scoped to selected policy.**  A
    completed sink-bound candidate is checked against the explicitly selected
    context before emission; unrelated registered contexts are not applied.

11. **No new external runtime dependency.**  Renderer selection, rendering, and
    emission remain implementable with Bash facilities only.

12. **No implicit syslog dependency.**  The default design requires neither
    rsyslog nor syslog-ng nor an open syslog port.

13. **Redirection remains meaningful.**  `./script` and `./script 2>run.log` may
    intentionally choose different textual renderers under `format=auto` because
    the consumer attached to standard error changed.

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

9. bashlog does not promise to discover or automatically redact sensitive data.
   A developer who does not explicitly select an appropriate context receives
   ordinary unredacted logging behavior.

10. A selected logging redaction context does not promise to match across logical
    field boundaries or against renderer punctuation that does not yet exist when
    primary redaction occurs.

11. Final verification is not promised to be free of conservative false-positive
    suppression when renderer-generated syntax itself matches a rule in the
    explicitly selected context.

## Adversary and Failure Model

This decision accounts for:

- a developer who writes the application without knowing its final deployment
  environment;
- a developer who intentionally chooses whether a particular logging call should
  use redaction;
- the same script moving from a terminal to systemd, Docker, Podman, cron, CI, or
  an orchestrator without source changes;
- standard error being redirected for one invocation but not another;
- misleading environment variables that appear to identify systemd or a
  container but no longer describe the actual file descriptor;
- a formatted message containing spaces, quotes, backslashes, tabs, newlines, or
  other characters requiring logfmt encoding;
- a registered secret containing characters that will later require renderer
  escaping;
- a protected value appearing in a tag rather than the message;
- a failure while transforming one of several caller-controlled fields;
- renderer-generated syntax that happens to satisfy a matcher in the explicitly
  selected context during final verification;
- a downstream parser expecting deterministic field names and ordering;
- a caller explicitly forcing human output into a non-terminal or logfmt output
  onto a terminal;
- and a future maintainer tempted to add platform detection or automatic
  redaction because one specific use case would become more convenient.

The decision does not attempt to defend against a malicious downstream log
consumer.  Once a verified record crosses standard error, storage, retention,
forwarding, access control, and downstream parsing are outside bashlog's process
boundary.

The decision also does not protect a logging call from sensitive data that the
developer chose to emit without selecting redaction.  That is application policy,
not a redaction-engine failure.

## Operational Constraints

- Standard error MUST remain the normal logging sink.
- Format mode MUST be one of `auto`, `human`, or `logfmt`.
- Format mode MUST default to `auto`.
- `auto` MUST resolve only through `[[ -t 2 ]]`.
- TTY standard error under `auto` MUST select `human`.
- Non-TTY standard error under `auto` MUST select `logfmt`.
- The canonical severity MUST remain present in human and logfmt output.
- Severity threshold decisions MUST remain independent of renderer selection.
- Redaction MUST remain opt-in for logging calls.
- Registering rules MUST NOT create an ambient or automatically applied logging
  context.
- A logging call without explicit context selection MUST NOT be inspected against
  registered redaction contexts.
- Primary logging redaction MUST occur on caller-supplied semantic fields before
  renderer-specific encoding or decoration when a context is explicitly selected.
- The formatted message and each tag MUST be protected independently when a
  logging call selects a redaction context.
- Severity and bashlog-generated timestamp fields MUST NOT be transformed by the
  primary logging redaction pass.
- Failure to transform or verify any protected field MUST suppress the entire
  record.
- Logfmt output MUST contain no bashlog-owned ANSI color sequences.
- Logfmt field order and escaping MUST be deterministic and normatively
  specified before implementation is accepted.
- The completed output MUST receive final non-transforming verification only
  against the explicitly selected context before emission.
- Renderer encoding MUST NOT be used as a substitute for primary redaction.
- bashlog MUST NOT infer Docker, Podman, systemd, journald, OpenRC, Kubernetes,
  Swarm, or another deployment environment for normal renderer selection.
- bashlog MUST NOT invoke `logger` or another external system-logging command.
- bashlog MUST NOT open an implicit TCP or UDP syslog sink.
- Invalid format configuration MUST fail atomically without changing prior state.
- A future direct syslog/network transport MUST require separate architectural
  review.

## Considered Alternatives

### Automatically Apply Redaction to Every Logging Call

bashlog could treat the existence of registered rules as sufficient reason to
apply redaction automatically, or it could apply every active context to every
message.

It was rejected because bashlog does not own the application's sensitivity policy.
Automatic application would create surprising transformations, increase false
positive suppression, add unnecessary work to unrelated logging calls, and make
context registration have hidden global consequences.  More fundamentally, it
would replace an explicit developer decision with library policy.

The project instead provides a strong mechanism that the developer invokes
explicitly.  Once invoked, the mechanism is fail-closed; until invoked, bashlog
does not pretend to know that redaction is required.

### Maintain an Ambient Current Redaction Context

A global current context would reduce repetition for applications that redact
most logging calls.

It was rejected because ambient state makes it harder to determine from a call
site whether redaction is active and can silently affect unrelated code sharing
the same Bash process.  Explicit `--context CONTEXT` selection keeps the security
choice visible where the logging operation occurs.

### Redact the Serialized Logfmt Line

The existing single-renderer implementation redacts a complete rendered human
candidate, so applying the same approach after logfmt serialization initially
appears consistent.

It was rejected because logfmt escaping would then become part of secret-matching
semantics.  A registered value containing quotes, backslashes, newlines, or other
encoded characters would require the redactor to understand the serializer's
representation before it could locate the original semantic value.  Every future
renderer would create the same coupling.

Protecting semantic caller data first keeps redaction independent of presentation
syntax.

### Redact One Canonical Rendered String and Convert It to Other Formats

A canonical intermediate textual representation could be redacted once and then
parsed or transformed into human/logfmt output.

It was rejected because it would create an unnecessary serialization/parsing
cycle and would make presentation delimiters part of the security model.  The
logical fields already exist before rendering and are the clearer boundary.

### Transform Severity and Timestamp Through the Redaction Context

Applying the selected context to every logical field would most closely resemble
the first implementation's complete-candidate transformation.

It was rejected because severity and bashlog-generated timestamps are
library-owned metadata rather than caller secret-bearing application values.
Allowing arbitrary rules to rewrite those fields would also complicate renderer
invariants such as the requirement that `level` carry the canonical severity.
They remain covered by final verification so a selected context that conflicts
with library-generated output still fails closed rather than emitting a matching
candidate.

### Omit Final Verification After Rendering

Once caller fields have been redacted before serialization, a second verification
step might appear redundant.

It was rejected because ADR-024's immediate pre-emission fail-closed check is a
valuable defense in depth when redaction has been explicitly selected.  Renderer-
owned punctuation or escaping can create new byte sequences even when protected
fields are clean.  The final check is therefore retained as verification only,
without reopening transformation.

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
timestamp policy, explicitly selected redaction policy, and sink.

The developer remains in control of whether redaction is active for a logging
call.  This means bashlog will intentionally emit unredacted caller data when the
developer has not selected a context.  That is not a failure of the security
boundary; no redaction boundary was invoked for that call.  The tradeoff is
accepted because hidden application policy would be more surprising and would
undermine the project's explicitness and agency principles.

The redaction architecture also becomes cleaner when invoked.  Application-
controlled data is protected before presentation begins, so human formatting,
logfmt quoting, and future renderers do not need to become secret-aware.  This
changes the logging pipeline's use of redaction from the first implementation's
complete-rendered-candidate transformation, so the change must be reflected
explicitly in the public specification, tests, and Doxygen contracts when these
proposed decisions are ratified.

The final verification boundary remains conservative for calls that select a
context.  It may suppress a record when renderer-generated syntax happens to
match a rule in that selected context.  That cost is accepted initially because
preserving fail-closed output is more important than maximizing emission in an
unusual rule collision.

The logfmt renderer still adds meaningful implementation and testing work.
Escaping must be deterministic and parser-compatible, but it is no longer part of
the primary secret-discovery problem.

The architecture avoids a larger cost: bashlog does not become a platform-
detection, application-policy, or log-transport framework.  systemd, Docker,
Podman, orchestration systems, and shell redirection continue to do what they
already do well with standard error.

## Source Lineage

This decision extends:

- ADR-013's narrow library/caller responsibility boundary;
- ADR-014's pure-Bash runtime and explicit external-command boundary;
- ADR-017's common logging pipeline and standard-error emission model;
- ADR-018's explicitly opt-in redaction security obligation;
- ADR-019's requirement that critical behavior remain directly auditable;
- ADR-024's fail-closed final output boundary;
- and ADR-025's timestamp, tag, and human-color presentation decisions.

The developer-owned context-selection rule is not new architecture invented by
this ADR.  It preserves ADR-018 and the initial logging API's existing explicit
`--context CONTEXT` model while adapting the transformation ordering for multiple
renderers.

The logical-record ordering follows the same separation-of-concerns principle:
application data is transformed according to explicitly selected security policy
before presentation code serializes it for a particular audience.

The logfmt choice follows established logfmt prior art while explicitly
acknowledging that logfmt has not been formally standardized.  bashlog therefore
owns the exact syntax it promises rather than outsourcing correctness to an
informal name.

## Superseded Decisions

If Accepted, this ADR SHALL supersede only the following portions of earlier
Accepted decisions:

- ADR-017 and the current public specification insofar as they require the logging
  pipeline to render a complete `level: message` candidate before explicitly
  selected primary redaction transformation;
- ADR-024 insofar as its wording assumes that final verification is immediately
  preceded by transformation of that same complete rendered candidate.

The following earlier principles remain in force:

- all bashlog-provided logging helpers converge through one security-sensitive
  pipeline;
- redaction remains opt-in and context selection remains explicit;
- an explicitly selected redaction context creates a fail-closed logging
  obligation;
- rule ordering and matcher semantics remain those defined by ADR-021 through
  ADR-023;
- the completed sink-bound candidate receives non-transforming final verification
  against the selected context before emission;
- no iterative fixed-point repair is introduced;
- safe diagnostic behavior remains governed by ADR-024.

This ADR does not supersede `bashlog_redact` semantics.  That public function
continues to transform and verify the exact caller-supplied string only when the
developer invokes it explicitly.

## Open Questions and Follow-Ups

- The normative specification must define exact per-field logging redaction and
  the transition from the current complete-candidate implementation while
  preserving explicit `--context` selection.
- Feasibility tests must establish the exact pure-Bash quoting and escaping
  algorithm for the bashlog logfmt profile on Bash 4.3.
- Compatibility fixtures should be parsed by one or more established logfmt
  implementations before the specification calls the renderer compatible.
- The public specification must define exact behavior for embedded newlines and
  other representable control characters under logfmt.
- Tests must prove that registered contexts remain inert for logging calls that do
  not explicitly select them.
- Tests must cover renderer-created final-verification matches so the fail-closed
  behavior is deliberate rather than accidental.
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
- ADR-021: Redaction Rule Registration, Ordering, and Replacement Semantics
- ADR-022: Fixed-String Redaction and Multibyte Guarantees
- ADR-023: Glob and ERE Redaction Semantics
- ADR-024: Final Redaction Verification and Fail-Closed Output Boundary
- ADR-025: Optional Presentation Metadata, Tags, and Color
