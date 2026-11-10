# ADR-034: Explicit Destinations, Context Defaults, and Deferred Logging Queues

Date: 2026-11-09

## Status

Accepted

For a decision prepared in a pull request, merging the pull request constitutes
acceptance of the design.  Acceptance of this ADR does not mean the proposed
public functions are implemented or available in released artifacts.  The
Accepted public behavior specification and implementation must be updated
together before this capability is described as shipped.

## Intent and Documentation Posture

This record captures the decision to make the destination of a bashlog record
explicitly selectable and to support named, in-memory, deferred-delivery queues.
It preserves the default immediate STDERR behavior, caller-owned application
lifecycle, and opt-in redaction.  It also defines exact failure and queue
semantics so implementation does not silently make consequential policy choices.

This is intentionally a detailed contract decision.  Deferred delivery changes
when output crosses an external boundary, introduces process-local retention,
and creates new questions about timestamp, presentation, redaction, and partial
writes.  Those questions must be answerable from this record without inferring
intent from a future implementation.

## Context

The current bashlog implementation validates a logging call, filters by
severity, constructs the formatted message, applies any explicitly selected
redaction context, renders human or logfmt text, finally verifies protected
output, and emits one record to STDERR.  All severity helpers converge through
`bashlog_log`.  This behavior is useful for normal operation, but some scripts
should accumulate selected messages and display them together at a deliberate
point, including from a caller-installed `EXIT` trap.

The original idea distinguished a message queue from a stream destination.
Discussion established that both are better represented as a single explicit
destination value: STDERR, STDOUT, or `queue:NAME`.  A caller may also want a
global default destination or a default associated with a particular redaction
context.  Another use case requires extracting an accumulated queue to a shell
variable for application-managed transformation and possible re-enqueueing.

The existing governance creates important boundaries:

- ADR-013 prohibits bashlog from installing traps or owning application control
  flow.
- ADR-014 requires pure Bash runtime behavior, with a Bash 4.3 compatibility
  floor under ADR-002.
- ADR-015 requires namespaced public API functions.
- ADR-017 requires a single policy/redaction/rendering pipeline and distinct
  return statuses for emission errors.
- ADR-018 and ADR-024 require explicit redaction to fail closed.
- ADR-026 defines routine STDERR transport, per-call TTY-sensitive rendering,
  and final verification immediately before emission.
- ADR-020 makes redaction-context destruction irreversible in one Bash process.

This decision refines only the portions of those contracts identified below.
It does not authorize file or network transport.

## Decision Drivers

- Preserve current output by default for every existing compliant caller.
- Express destination selection with one coherent and extensible `--to` option.
- Support multiple independent deferred queues without subprocesses or files.
- Let a selected context carry an optional default destination while keeping
  redaction context selection explicit.
- Retain FIFO order and finished-record identity within each named queue.
- Avoid accumulating unredacted semantic messages while waiting for a flush.
- Keep an application in charge of `EXIT` traps, queue lifetime, and retries.
- Avoid silent data loss on an unsuccessful flush, while acknowledging that
  partial writes make exactly-once delivery impossible.
- Keep errors and safe diagnostics distinct from ordinary routed records.
- Provide a safe, lossless way to extract a queue into a caller-owned variable.
- Keep the contract readily testable across all shipped artifact flavors.

## Decision

### Destination Grammar and Routing

A destination MUST match this anchored, case-sensitive ASCII grammar:

```text
^(STDERR|STDOUT|queue:[A-Za-z0-9]+)$
```

`STDERR` means immediate emission to file descriptor 2.  `STDOUT` means
immediate emission to file descriptor 1.  `queue:NAME` means deferred
appending to a named, process-local queue.  The name is nonempty, ASCII
alphanumeric, and case-sensitive.  Thus `queue:errors` and `queue:Errors`
refer to different queues.  Lowercase `stderr`, `stdout`, `queue:`, and
names with underscores, dashes, spaces, or colons inside the name are invalid.

These destination tokens are data, not shell programs or command expressions.
The runtime MUST NOT evaluate, source, interpolate, or execute their contents.

For this decision, there are exactly three supported destination forms.  The
prefix model leaves room for later destination classes; no syntax or runtime
behavior for file paths or remote logging is reserved by this ADR.

### Public Routing API

The selected API shape is:

```bash
bashlog_destination_set --to STDERR
bashlog_destination_get
bashlog_destination_reset

bashlog_destination_set --context secrets --to queue:errors
bashlog_destination_get --context secrets
bashlog_destination_reset --context secrets

bashlog_error --context secrets --to STDOUT 'request failed'
bashlog_error --context secrets 'request failed'
```

The global default is `STDERR`, initially and after a global reset.  A global
getter returns the configured global destination.  The context getter returns
the effective destination for that explicitly identified active context: its
override if present, otherwise the global default.

Destination resolution for a logging operation SHALL be:

1. An explicit per-call `--to DESTINATION`;
2. the destination override of a valid, explicitly selected `--context`;
3. the global default, initially `STDERR`.

Configuration MUST NOT implicitly select a redaction context.  A context
destination applies only when the logging call explicitly selects that context.
A per-call `--to` overrides a context default without changing that default.
A context destination is routing policy, not a mandatory security restriction.

A call to `bashlog_destination_set --context CONTEXT` requires an existing
active redaction context; it MUST NOT create or revive one.  Invalid or
unavailable contexts retain existing context validation/failure semantics.
Context-specific reset removes the override and restores inheritance rather
than setting an explicit `STDERR` value.  Global reset restores `STDERR`.

Invalid destinations and invalid option shapes return usage status `64` and
leave configuration and queued records unchanged.  Configuration getters,
setters, and resets are explicit; merely sourcing bashlog changes no caller
trap or shell policy.

### Logging-Call Integration

The existing generic logger and all severity helpers MAY accept one optional
`--to DESTINATION` before the format string, alongside `--context` and
repeatable `--tag`.  `--` still terminates option parsing.  Duplicate `--to`
options are invalid.  A valid destination MUST be resolved before any sink
write or enqueue; invalid input MUST NOT leak the caller's message.

Existing calls without destination configuration or `--to` continue to write
one final record to STDERR, with existing threshold, message construction,
tag, timestamp, and redaction semantics unchanged.

The ordinary pipeline remains common to all destinations:

```text
validate options, context, and destination
    -> severity threshold
    -> printf-style semantic message construction
    -> optional timestamp acquisition
    -> optional selected-context transformation of message/tags
    -> choose presentation and render a complete record
    -> optional final non-transforming verification of rendered record
    -> deliver verified bytes immediately or append to named queue
```

A threshold-suppressed valid call returns success without enqueuing content
or constructing a record, as under the existing logging contract.  Redaction
failures MUST remain fail-closed for both immediate and deferred destinations.

### Rendering and TTY Behavior

Rendering is completed at the logging call, including before enqueueing.
Each queue stores already-rendered, complete records in their original FIFO
order.  Neither a later renderer configuration change nor the destination
chosen for a flush may reinterpret previously queued records.

For `format=auto` and `color=auto`, the observed file descriptor SHALL be:

- descriptor 2 for immediate `STDERR`;
- descriptor 1 for immediate `STDOUT`;
- descriptor 2 at enqueue time for `queue:NAME`.

The deferred destination has no terminal of its own, so evaluating STDERR
at enqueue time is the deterministic compatibility choice.  In particular,
flushing a queue later to STDOUT does not rerender records as though they had
originally been logged to STDOUT.  Explicit `human` or `logfmt` modes continue
to override automatic format selection.  Existing ANSI restrictions for
logfmt and human severity tokens remain in effect.

Timestamps, when enabled, describe the logging/enqueue operation, not the
later flush.  A queued record carries exactly the completed bytes that an
equivalent immediate record would have produced at enqueue time, including
its terminating newline.

### Redaction and the Queue Security Boundary

For `--context CONTEXT`, primary redaction and final verification MUST
complete successfully **before** a rendered record is appended to a queue.
The queue SHALL contain only the resulting, already-processed rendered text,
never a retained original semantic message awaiting later redaction.

After successful insertion, bashlog treats that rendered record as immutable
through its public queue operations.  Flush writes the stored bytes without
rerendering, transforming, or reverifying them against any context.  A later
addition of redaction rules is not retroactive.  A context may be destroyed
after records have been queued without destroying or invalidating those
already-processed records.

This intentionally refines ADR-024 and ADR-026's rule that selected-context
final verification occurs immediately before actual sink emission.  For this
new deferred route, the last redaction verification occurs immediately before
a record enters its queue; subsequent delivery is a byte-preserving replay
of that verified record.  No additional formatting, prefixes, or caller
content may be inserted after that verification by bashlog.

This is a bounded security guarantee, not a claim that historic output
satisfies subsequently adopted rules.  Developers who change redaction
policy after enqueueing own the decision to extract, reprocess, discard, or
re-enqueue older queued content.  Once data is extracted to a caller variable,
subsequent transformations and output are caller-owned.

An extracted combined block re-enqueued through `bashlog_error` or a similar
logger becomes a **new** log record.  It does not reconstruct the individual
original records or preserve their individual severity and metadata.

### Queue Lifecycle and Operations

The proposed public operations are:

```bash
bashlog_queue_flush errors
bashlog_queue_flush errors --to STDERR
bashlog_queue_flush errors --to STDOUT
bashlog_queue_extract errors buffer
bashlog_queue_clear errors
```

Queue-management functions accept a queue **name** such as `errors`, not
`queue:errors`.  Names follow `[A-Za-z0-9]+` and are case-sensitive.

A queue is created implicitly on its first successfully eligible append.
There is no required create operation.  Multiple queues are independent;
records preserve FIFO order within a queue.  No global ordering guarantee
across different queues is established.

`bashlog_queue_flush NAME` defaults to immediate STDERR emission, regardless
of the configured global or context destination.  Its optional `--to` accepts
only `STDERR` or `STDOUT`; queue-to-queue flushing is not supported by this
operation.  A successful flush emits the stored records as already rendered,
then clears the queue.  The empty or nonexistent queue is a successful no-op.
No automatic flush occurs on sourcing, normal shell exit, error, signal,
or queue growth.

`bashlog_queue_clear NAME` discards queued data without output.  Clearing
an empty or nonexistent queue is a successful no-op.  Clearing does not alter
destination configuration or redaction contexts.

`bashlog_queue_extract NAME VARIABLE` assigns the exact concatenation of
complete queued record bytes, including embedded and trailing newlines, to
a caller-named Bash variable without writing to either standard stream.
A successful extraction clears the queue.  Extracting an empty or nonexistent
queue succeeds and assigns an empty string.  Bash cannot represent embedded
NUL; queue/extraction does not extend that boundary.

The variable argument MUST be an appropriate valid Bash identifier that can be
assigned without evaluating caller-supplied code.  The implementation SHALL
reject unsafe shell special variables, internal bashlog state, and assignments
that would violate the caller's variable constraints; failed extraction MUST
leave the queue intact.  The design does not require `eval`, caller-generated
code, external commands, or unsafe name interpolation.

Queue state is process-local Bash state.  Normal Bash subshell and command
substitution semantics apply: modifications in a child environment do not
propagate to the parent shell.

### Partial Writes, Retries, and Resource Ownership

An unsuccessful immediate write or queue flush SHALL report an emission error
using the existing status `74`.  A failed flush MUST leave the **entire**
queue available for caller-controlled retry, even if the destination already
received a prefix of the bytes.  A successful flush clears that queue.

No guarantee is made that output to a terminal, pipe, or file descriptor is a
single atomic operating-system write, or that a flush is all-or-nothing at the
destination.  A retry after a partial write may duplicate previously emitted
bytes.  The library MUST NOT silently discard an uncertain suffix or claim
exactly-once delivery.

An unsuccessful extraction MUST not consume the queue.  Internal transformation
or variable-assignment failures are distinct from successful extraction;
argument validation uses `64`, and no partial result is advertised.

Queues have no configured size limit in the initial design.  Their growth is
bounded only by the Bash process's available memory and execution environment.
The library does not automatically flush, evict old records, spill to disk,
or apply backpressure.  Callers own queue lifetime, sizing discipline,
flushing, extraction, and clearing.  Process termination before a successful
flush loses buffered records.

### Context Destruction, Diagnostics, and Caller Traps

A redaction context's optional default destination is context-owned
configuration.  Destroying a context discards its destination override along
with its active state; it does not clear queues to which earlier records
were directed.  The context name remains unavailable for reuse under ADR-020.
Previously queued, verified records remain flushable.

Safe redaction-failure diagnostics follow their preexisting immediate STDERR
path.  They are not routed to STDOUT or into a selected queue, including when
the attempted logging operation uses one of those destinations.

bashlog SHALL NOT install an `EXIT`, `ERR`, signal, or other trap.  A caller
may deliberately arrange `bashlog_queue_flush` inside a caller-owned trap
and preserve the application's original exit code.  The library does not
automatically turn a failed logging call into application termination.

### Deferred Destination Types

A typed destination grammar permits future explicit forms such as file output
or remote logging, but those are illustrative use cases only.  This ADR
establishes no implementation, accepted prefix, path grammar, protocol, or
remote-transmission security promise for any of them.

Each additional destination class requires a separate architectural review of
parsing, trust boundaries, failure behavior, and runtime dependencies.
In particular, remote transports would revisit ADR-014's pure-Bash boundary;
file destinations would revisit permissions, symlinks, paths, and append
semantics.  Unknown prefixes remain invalid in the current grammar.

## Promises

- Existing ordinary logging remains immediate STDERR by default.
- Destination input uses one precise, case-sensitive accepted grammar.
- Resolution is per-call, then context override, then global default.
- Selecting a context remains explicit and continues to control redaction.
- All severity helpers use the common pipeline regardless of destination.
- A queued record is completely formatted, optionally redacted, and finally
  verified at enqueue time, before its bytes are stored.
- FIFO order is preserved within each queue.
- Queued bytes are never rerendered or silently modified by bashlog on flush.
- A successful flush or extraction clears the chosen queue.
- Failed flush or extraction preserves the entire queue.
- Safe redaction-failure diagnostics retain their immediate STDERR behavior.
- No traps, external commands, automatic flushing, or durable storage are added.

These promises become testable product commitments only when the public
specification, runtime implementation, and released artifact contract tests
implement this decision.

## Non-Promises

- No exactly-once or atomic write guarantee across partial writes or retries.
- No durable queue persistence across process termination or power failure.
- No queue memory quota, overflow policy, or automatic drain.
- No global ordering across independently named queues.
- No automatic enforcement of newly registered redaction rules on older records.
- No secure erasure of historical queue bytes after clearing or extraction.
- No hostile-same-interpreter isolation of bashlog's process-local variables.
- No protection from caller-side tracing, hostile downstream consumers,
  application logging outside bashlog, or caller-managed re-emission.
- No recovery of per-record severity/timestamps from a combined extracted block.
- No shell-variable support for NUL bytes.
- No file, syslog, rsyslog, journald, socket, or network transport.
- No claim that an Accepted ADR alone constitutes a shipped feature.

## Adversary and Failure Model

Material conditions include malformed destination syntax; unexpected option
order; invalid or destroyed contexts; protected values in format arguments or
tags; redaction verification failures; rule changes after enqueuing; unsafe
variable names; attempts to assign readonly or Bash special variables; broken
pipes and closed file descriptors; short or partially successful output;
unbounded queue growth; early process termination; and shell subshell isolation.

The relevant assets are caller-provided sensitive values, selected redaction
contexts, finished queued records, configured destination state, the integrity
of the application's STDOUT data channel, and availability of accumulated logs.

Risk is reduced by one validation/redaction pipeline, atomic queue-state
mutation when an operation reports success, literal destination parsing,
immediate fail-closed verification at enqueue time, preserving entire queues
on ambiguous writes, and leaving exit traps to the application.

The accepted tradeoff is intentional: once a record has been verified and
queued, it is replayed without comparing it against later redaction-rule
changes.  That choice minimizes deferred secret retention and avoids dependent
context-lifecycle state, but means confidentiality relative to future rules
is not promised.

## Operational Constraints

- MUST target Bash 4.3+ and use builtins/language features only at runtime.
- MUST NOT change existing ordinary STDERR logging without explicit opt-in.
- MUST reject unrecognized destination forms with `64` and no record emission.
- MUST validate context and destination before constructing sink-bound content
  after the existing option-validation boundary.
- MUST apply selected redaction and final verification before queue append.
- MUST NOT store unredacted semantic message copies for later processing.
- MUST use the selected immediate file descriptor for `auto` presentation.
- MUST use descriptor 2 for `auto` when enqueuing to a named queue.
- MUST preserve FIFO record order and literal byte content through flush.
- MUST retain the whole queue after a failed flush or extraction.
- MUST avoid `eval` and any generated shell code for name-based operations.
- MUST preserve context lifecycle and safe diagnostic semantics.
- MUST NOT install traps, launch commands, persist queues, or transport remotely.
- MUST exercise equivalent behavior across development, ordinary, and minified
  artifacts, plus the Bash 4.3 compatibility contract.

## Considered Alternatives

### Separate `--queue` and `--stream` Options

Two options could describe buffering and transport independently, but would
create redundant parameters and conflict rules.  Rejected in favor of one
destination abstraction and queue-specific lifecycle operations.

### Treat `STDERR` and `STDOUT` as Special Queue Names

`--queue STDERR` is terse, but it conflates queue storage with immediate
delivery and reserves otherwise ordinary names.  Rejected in favor of typed
`--to` destinations.

### Caller-Owned Buffer Variable Per Logging Call

Using a caller variable for each log would avoid a registry but would
complicate validation, accidental mutation, aggregation, and ownership of
redaction/record ordering.  Rejected as the primary interface.  Explicit
`bashlog_queue_extract` retains a safe caller-variable workflow.

### Defer Formatting or Redaction Until Flush

Deferred formatting could adapt `auto` to a later stream.  Deferred redaction
would retain raw potentially sensitive values and depend on contexts still
existing at flush time.  Both add complexity and an avoidable security exposure.
Rejected; queues contain fully rendered, verified records.

### Reverify Under the Current Context at Flush

This would apply updated rules but require retaining or recreating context
association and could prevent flushing after context destruction.  Rejected
because policy changes are developer-owned; this ADR deliberately refines
the earlier immediate-before-sink verification requirement for buffered records.

### Drop Messages or Remove a Written Prefix on Flush Failure

This would reduce replay duplication but risks silent loss when the target
observed only a partial write.  Rejected; retain the full queue and return `74`.

### Flush Automatically on Trap or Queue Size

Automatic draining might be convenient but creates unwanted lifecycle control,
unbounded side effects, and hard-to-predict timing.  Rejected; callers invoke
flushing and may install their own traps.

### Implement File and Remote Destinations Now

Potentially useful future capabilities would enlarge security, dependency, and
failure scope before a concrete need is approved.  Deferred without reserving
specific prefixes or semantics.

## Consequences

The new routing interface is additive and future-extensible; immediate STDERR
remains the default, while STDOUT use is always a deliberate routing choice.
Application writers gain named FIFO queues, context-sensitive defaults,
caller-controlled drains, and exact text extraction.

Implementation complexity increases in destination resolution, presentation
TTY selection, queue storage, and failure handling.  Explicit STDOUT output
expands bashlog's egress boundary, and storing completed records creates a new
process-memory retention concern.  CI must verify new behavior at the same
rigor as existing redaction and presentation contracts.

Deliver the change in cohesive, reviewable work: an Accepted ADR and decision
map first; then update the normative public specification and threat model
together with runtime code, source Doxygen, README, focused Bats tests,
Bash 4.3 coverage, and all artifact flavors.  The documentation-only decision
PR must not claim that the new public API already exists.

## Source Lineage

The decision grows out of the existing common `bashlog_log` pipeline, the
Accepted public behavior specification, the maintained threat model, and
the design discussion about deferring error summaries until application
shutdown.  It is a refinement, not a replacement of the library's purpose.

## Superseded and Refined Decisions

This ADR refines only the following prior constraints:

- **ADR-026:** STDERR remains the default sink, but an explicitly selected
  `STDOUT` sink is permitted.  `auto` presentation resolves against the
  immediate selected stream or against STDERR for queues at enqueue time.
- **ADR-024 and ADR-026:** selected-context final verification occurs before
  insertion into a named queue rather than immediately before the subsequent
  sink write, provided the verified bytes remain unchanged by bashlog.
- **ADR-017:** delivery may append an already processed record to a named queue,
  which is later explicitly drained.  Its common pipeline, severity,
  formatting, and fail-closed principles remain in force.

ADR-013's no-trap requirement, ADR-014's pure-Bash runtime boundary, ADR-015's
namespace contract, and ADR-020's context lifecycle remain in force.

## Open Questions and Follow-Ups

There are no unresolved choices among the six agreed queue policies.  The
implementation still needs evidence for exact variable-assignment behavior,
failure preservation under short writes, Bash 4.3 compatibility, and source-
time non-invasiveness.

Create focused tests for global/context/per-call precedence, reset
inheritance, invalid and case-sensitive names, empty queues, FIFO delivery,
TTY-sensitive rendering, timestamps at enqueue time, context destruction,
redaction failures and negative leakage, extraction's exact trailing newlines,
invalid/readonly variable targets, partial write retries, and the absence of
automatic traps or runtime commands.

Do not add `file:`, remote transport, automatic queue limits, or automatic
flushing while implementing this decision.

## Related Decisions

- ADR-002: Bash Runtime and Portability Baseline
- ADR-008: Documentation-Driven, Test-Second Development
- ADR-009: Observable Behavior Testing
- ADR-013: Sourceable Library Scope and Responsibility Boundary
- ADR-014: Pure Bash Runtime and External Command Boundary
- ADR-015: Namespaced Public API and Caller-Owned Convenience Wrappers
- ADR-017: Logging Pipeline, Levels, Formatting, and Emission
- ADR-018: Redaction as an Opt-In Security Boundary
- ADR-020: Redaction Context Lifecycle and State Model
- ADR-024: Final Redaction Verification and Fail-Closed Output Boundary
- ADR-025: Optional Presentation Metadata, Tags, and Color
- ADR-026: Adaptive Human/Logfmt Rendering and Stderr Transport
- ADR-027: Configurable Severity Token Styles
- `doc/bashlog-spec.md`: Current Accepted Public Behavior Specification
- `doc/threat-model.md`: Current Maintained Threat Model
