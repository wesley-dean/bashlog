# ADR-017: Logging Pipeline, Levels, Formatting, and Emission

Date: 2026-08-30

## Status

Accepted

## Intent and Documentation Posture

This ADR defines the shape of bashlog's logging pipeline and identifies which
parts of the older shell logging implementation are architectural behavior worth
carrying forward.

The intent is not to freeze every visible formatting character before
implementation experiments and tests exist.  It is to establish the ordering and
responsibility boundaries that future formatting, severity, redaction, and sink
work must preserve.

This distinction matters because redaction is not an optional post-processing
feature bolted onto unrelated output functions.  The logging architecture must
make it difficult for a new severity helper or convenience module to bypass the
same security-sensitive emission path.

## Context

The older shell support library contains a useful logging implementation with
several capabilities that bashlog intends to preserve conceptually:

- normalized severity levels;
- a configurable log threshold;
- helper functions such as debug, info, warning, and error;
- `printf`-style caller formatting;
- optional visible formatting such as color;
- optional timestamp/tag metadata;
- centralized rendering;
- and a common low-level logging function through which higher-level helpers
  pass.

The older implementation also contains behavior bashlog intentionally does not
carry forward as-is:

- invocation of external `date` for timestamps;
- invocation of external `hostname` as a fallback;
- invocation of external `logger` for syslog;
- stack-trace transformation using external tools;
- generic global function names as the only interface;
- and automatic application error trapping.

The valuable architectural idea is therefore not "copy the old logger."  It is
that logging should converge through one predictable pipeline.

A redaction-capable logger makes pipeline ordering more important.  Consider the
following possible orders:

```text
redact -> printf-format -> emit
```

and:

```text
printf-format -> redact -> render -> emit
```

The first can fail if formatting introduces a sensitive value after redaction.
The second allows the library to redact the actual message text that is about to
be rendered.

A similar issue exists for metadata.  If caller-controlled tags or other fields
are appended after redaction, a guarantee phrased as "registered fixed secrets do
not reach a bashlog sink" can be violated even though the message body was
redacted correctly.

The pipeline therefore needs one final security boundary immediately before
emission, after the complete sink-bound text is known.

## Decision Drivers

- Preserve the useful severity and formatting behavior of the earlier logging
  implementation.
- Ensure every shipped logging helper converges through the same security-
  sensitive path.
- Make redaction occur after caller `printf`-style message construction rather
  than before it.
- Prevent debug or high-verbosity output from becoming a redaction bypass.
- Keep rendering and emission separate enough to support testing and future
  caller composition.
- Avoid external runtime dependencies.
- Keep output behavior deterministic and inspectable.
- Allow visible formatting features without allowing them to introduce an
  unredacted late-stage bypass.
- Keep exact public formatting and sink semantics in a normative specification
  once they are stable.

## Decision

bashlog SHALL implement logging as a staged pipeline with one common path from
message construction to sink emission.

The conceptual order SHALL be:

```text
caller arguments
    -> severity/threshold decision
    -> printf-style message construction
    -> logging metadata and presentation rendering
    -> redaction of sink-bound text
    -> final redaction safety checks required by the accepted redaction ADRs
    -> emission
```

The exact internal function boundaries may differ, but the observable security
ordering MUST preserve the principle that the complete text crossing a bashlog
sink is subject to the configured redaction policy immediately before emission.

### Severity and Threshold Behavior

bashlog SHALL provide normalized logging severity levels and a configurable
threshold or equivalent level policy.

The initial implementation SHOULD retain the conventional severity vocabulary
used by the older logger where doing so is useful and unsurprising.  The exact
public names, aliases, numeric mappings, and default threshold SHALL be defined in
`doc/bashlog-spec.md` before stable release.

Severity filtering SHALL be a logging policy decision, not a redaction bypass.
A message that is suppressed by level policy does not need to be emitted.  A
message that is permitted to continue MUST pass through the same redaction and
emission path regardless of severity.

Debug, trace-like, or high-verbosity output MUST NOT use a separate unredacted
sink.

### Message Construction

Public severity helpers SHALL support safe, documented message construction.  The
older logger's `printf -v` approach is a useful model because it permits formatted
messages to be constructed in a variable before any sink is used.

If bashlog accepts a format string and arguments, formatting SHALL occur before
the final redaction boundary so that sensitive values introduced through format
arguments are present in the text being inspected.

The project MUST document that a format string participates in Bash `printf`
semantics.  Caller data that should be treated literally SHOULD be passed as an
argument to a literal format such as `%s`, rather than used as the format string
itself.

### Rendering and Metadata

bashlog MAY support presentation features such as:

- severity labels;
- optional color;
- timestamps produced with Bash-native facilities;
- application tags or names;
- and other narrowly logging-related metadata.

Such features MUST remain within the pure-Bash runtime boundary established by
ADR-014.

Caller-controlled metadata that becomes part of emitted text SHALL be treated as
sink-bound text and SHALL NOT be appended after the final redaction boundary.

The exact default rendered shape is intentionally deferred to the specification.
This ADR establishes the security ordering and common-pipeline requirement.

### Rendering Versus Emission

The implementation SHOULD preserve a distinction between producing the final
line and writing it to a sink.  This separation improves testability and may
support future caller-owned integrations.

Any public render-only function, if adopted, MUST have a clearly documented
security contract.  A function described as returning redacted logging output
MUST perform the same required redaction as an emitting path.  An internal
pre-redaction renderer MUST NOT be exposed as though its output were safe for an
external sink.

### Emission

Every sink implemented by bashlog SHALL receive only text that has passed through
the required final redaction boundary.

The initial sink set SHOULD remain small.  Standard output, standard error, or
caller-provided file descriptors may be considered because they can be handled
with Bash redirection.  External syslog, network, or command-based sinks are
outside the runtime boundary unless a later ADR supersedes ADR-014.

Emission failure SHALL be distinguishable from successful emission through the
public return-status contract.  Failure semantics must not cause the library to
retry by sending the unredacted original through a different path.

## Promises

1. **One security-sensitive emission path.**  Every bashlog-provided severity
   helper eventually reaches the same required redaction boundary before output.

2. **Formatting precedes final redaction.**  Sensitive values introduced through
   supported message-format arguments are present when the final sink-bound text
   is redacted.

3. **Metadata cannot be appended after the security boundary.**  Caller-
   controlled text that bashlog adds to the visible log line is included in the
   text subjected to final redaction.

4. **Severity does not weaken redaction.**  Debug or verbose messages do not use
   a less protected output path.

5. **External syslog is not a hidden sink.**  bashlog does not invoke `logger` or
   another external command as part of its built-in emission path under the
   current architecture.

6. **Rendering and emission are inspectable stages.**  The implementation may
   separate them for clarity and testing, but no public "safe" render path may
   bypass required redaction.

## Non-Promises

1. This ADR does not yet promise a particular visible log-line format.

2. This ADR does not yet promise a specific set of severity names, aliases, or
   numeric values beyond the requirement for normalized severity policy.

3. This ADR does not promise that bashlog automatically discovers an application
   name, hostname, Git revision, or other external metadata.

4. This ADR does not promise built-in syslog or network logging.

5. This ADR does not promise that caller-side output performed outside bashlog
   passes through bashlog redaction.

6. This ADR does not make arbitrary caller format strings safe.  The normative
   API documentation must explain correct use of `printf`-style interfaces.

7. Suppressing a message because of severity policy is not evidence that its
   contents were safe; it merely means bashlog did not emit that message through
   the suppressed path.

## Adversary and Failure Model

This decision is intended to prevent architectural bypasses and ordering defects
including:

- a new `debug` helper printing directly instead of using the common logger;
- a convenience `die` helper emitting its own message before exiting;
- a formatter adding caller-controlled text after redaction;
- a color or timestamp renderer creating a second sink path;
- a public render helper returning pre-redaction text while callers assume it is
  safe;
- a syslog path receiving the original message while terminal output receives a
  redacted copy;
- a replacement or metadata field introducing a sensitive value late in the
  pipeline;
- an emission failure causing fallback to an unsafe path;
- and tests that validate only one severity while another bypasses the security
  boundary.

The model does not protect against callers that intentionally write secrets to
stdout, stderr, files, or external commands without using bashlog.

The model also does not protect against hostile same-process code that replaces
bashlog functions or file descriptors.  That limitation belongs to the broader
redaction threat model.

## Operational Constraints

- All public logging severity helpers MUST converge through a common emission
  architecture.
- Supported message formatting MUST complete before the final redaction boundary.
- Sink-bound metadata MUST be included before final redaction.
- No severity or verbosity level MAY bypass required redaction.
- No built-in sink MAY receive the original unredacted text after redaction is
  required.
- External `logger` or equivalent commands MUST NOT be invoked by bashlog under
  the current architecture.
- Render-only APIs, if public, MUST document whether their output has completed
  redaction and MUST NOT misrepresent pre-redaction text as sink-safe.
- Emission failure MUST NOT cause fallback emission of the original message.
- The normative specification MUST eventually define public severity names,
  threshold semantics, default formatting, sink selection, return statuses, and
  presentation options.

## Considered Alternatives

### Redact Before `printf`-Style Formatting

This might allow redaction rules to be applied to individual arguments before
message construction.

It was rejected as the sole security boundary because formatting can construct
or introduce text after that point.  The final complete sink-bound representation
must still be inspected before emission.

### Let Each Severity Function Render and Emit Independently

Separate `debug`, `info`, `warn`, and `error` implementations can be short and
straightforward initially.

It was rejected because duplicated sink logic makes it easier for formatting,
return semantics, and redaction behavior to drift.  A common convergence point
is more auditable.

### Redact Only the Message Body

Metadata such as tags, labels, and context names may appear harmless compared
with the message body.

It was rejected as a general guarantee boundary because caller-controlled text
can appear in metadata.  If bashlog promises that registered fixed secrets do not
reach its sinks, it should apply that obligation to the full caller-influenced
sink-bound representation.

### Preserve Built-In `logger` Integration From the Older Library

This would retain direct syslog support.

It was rejected because ADR-014 prohibits external runtime command execution and
because sending data to another process creates another redaction-sensitive
boundary.  Callers may compose an external integration explicitly.

### Make Presentation Formatting the Caller’s Entire Responsibility

bashlog could emit only raw message bodies and require callers to add timestamps,
labels, and colors themselves.

That would keep the library extremely small, but it would discard useful logging
functionality from the older implementation and make consistent behavior harder
for consumers.  bashlog may own narrowly logging-related presentation as long as
it stays within the pure-Bash and final-redaction boundaries.

## Consequences

The common pipeline becomes one of the most security-sensitive parts of the
project.  Changes to ordering deserve architectural review even when the visible
output appears unchanged.

Some internal work may be duplicated conceptually during rendering and final
verification in order to make guarantees strong and failure behavior obvious.
That cost is preferable to an optimized but difficult-to-audit pipeline.

The exact public appearance remains intentionally flexible until the
specification is drafted.  This lets implementation experiments determine which
old logging behaviors remain useful without weakening the foundational security
ordering.

## Source Lineage

This decision draws from the older `shell_script_library/base.bash` logging
pipeline, especially its use of a centralized low-level logging function and
`printf -v` message construction.

It also incorporates lessons from Bootstrap's human-centered logging ADR and
runtime logging module, while preserving bashlog's distinct purpose as a reusable
logging library rather than a single application's output layer.

## Open Questions and Follow-Ups

- Define the exact severity vocabulary and numeric ordering.
- Decide whether `warn`, `warning`, or both appear in the namespaced public API.
- Decide default output streams for each severity.
- Decide whether timestamps are default, opt-in, or omitted unless configured.
- Decide color defaults and terminal-detection behavior without external tools.
- Decide whether caller-provided file descriptors are supported as sinks.
- Decide whether a public redacted render-only API is valuable for caller-owned
  integrations such as syslog.
- Define emission and formatting return statuses in the normative specification.

## Related Decisions

- ADR-013: Sourceable Library Scope and Responsibility Boundary
- ADR-014: Pure Bash Runtime and External Command Boundary
- ADR-015: Namespaced Public API and Caller-Owned Convenience Wrappers
- ADR-018: Redaction as an Opt-In Security Boundary
- ADR-019: Readability, Auditability, and Rejection of Obscurity
