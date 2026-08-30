# ADR-014: Pure Bash Runtime and External Command Boundary

Date: 2026-08-30

## Status

Accepted

## Intent and Documentation Posture

This ADR defines what "pure Bash" means for bashlog and makes the external-command
boundary a deliberate architectural guarantee rather than an implementation
accident.

The project is expected to process potentially sensitive logging data.  Every
external process added to the runtime path creates another place where arguments,
environment, standard streams, inherited file descriptors, process metadata, or
sensitive data may cross a boundary that the library would then need to reason
about.  Avoiding those processes materially reduces both implementation
complexity and the surface that must be trusted.

This decision is intentionally explicit about the distinction between commands
invoked by bashlog and commands invoked by its caller.  Bash performs expansions,
including command substitution, before a shell function receives its arguments.
A useful trust model therefore has to identify ownership accurately rather than
attribute caller-side behavior to the library.

## Context

Traditional shell logging helpers often rely on external tools for operations
that appear ordinary:

- `date` for timestamps;
- `hostname` for host identification;
- `logger` for syslog emission;
- `sed`, `awk`, `grep`, or Perl for text transformation;
- hashing tools for attempts to hide or compare sensitive state;
- temporary files and helper programs for complex formatting.

Those choices are common and can be perfectly reasonable in application code.
They are not free in a library whose security value depends partly on limiting
where unredacted data can travel.

bashlog is also intended to be highly portable within its declared Bash runtime
floor.  A design that requires only Bash builtins, shell keywords, parameter
expansion, arithmetic, arrays, conditionals, and redirection has fewer host-level
capability assumptions than one that requires a collection of external
utilities.

The project has already adopted a broader responsibility principle: callers own
application data acquisition and application-specific transformation.  A caller
that wants the current Git revision may invoke `git`.  A caller that wants a
host-specific value may invoke an appropriate host utility.  A caller that wants
to hand already-redacted output to an external logging program may do so.

That composition should not weaken bashlog's own promise.

For example:

```bash
bashlog_info 'Application started at %s' "$(date -Is)"
```

causes Bash to execute `date` while preparing the arguments.  bashlog receives
the resulting string.  The external command was selected and invoked by the
caller, not by the library.

Similarly:

```bash
line="$(bashlog_render info 'message')"
logger -- "${line}"
```

would make `logger` a caller-owned integration if a render-only API is eventually
part of the accepted public contract.

The architecture should permit those compositions while keeping the library's
runtime behavior narrower.

## Decision Drivers

- Minimize the number of execution boundaries that can receive sensitive data.
- Keep redaction and logging behavior auditable inside one Bash process.
- Avoid runtime dependencies on external Unix utilities.
- Make portability depend primarily on Bash behavior rather than host tool
  inventories.
- Preserve caller freedom to use external tools deliberately.
- Keep failure semantics deterministic when PATH contents vary between systems.
- Reduce command-injection and quoting concerns associated with subprocess
  construction.
- Support testing that can prove the library works when external commands are
  unavailable.
- Distinguish build-time tooling from runtime behavior.

## Decision

bashlog SHALL invoke no external commands during runtime library operation.

For the purposes of this decision, runtime library operation includes:

- sourcing the released library artifact;
- configuring logging behavior through its public API;
- registering and applying redaction rules;
- formatting log messages;
- evaluating log levels;
- producing logging metadata owned by the library;
- rendering output;
- emitting output through sinks provided by the library;
- and executing namespaced convenience functions shipped as part of the
  artifact.

Runtime implementation SHALL use Bash language facilities and Bash builtins.
Examples include:

- `printf` and `printf -v`;
- `[[ ... ]]`;
- `case`;
- `read` where appropriate;
- `local`, `declare`, and `readonly`;
- indexed and associative arrays supported by the project's Bash floor;
- parameter expansion;
- arithmetic expansion;
- redirection;
- shell functions;
- Bash special variables;
- and Bash builtin time formatting if separately adopted.

The prohibition applies to direct and indirect library invocation of external
programs.  bashlog SHALL NOT hide an external command behind a helper function,
command name lookup, subshell, pipeline, or command substitution and still
represent itself as pure Bash.

The runtime prohibition does not apply to repository development, build,
documentation, test orchestration, dependency synchronization, release
verification, checksum creation, or CI.  Those workflows intentionally use tools
such as Make, bashdeps, Doxygen, Bash-Minifier, ShellCheck, shfmt, Bats, Git,
SHA-256 utilities, and other development infrastructure.  They are outside the
consumer runtime boundary.

The prohibition also does not apply to external commands intentionally invoked by
callers before or after invoking bashlog.  Caller-side command substitution,
pipelines, process substitution, or downstream integrations remain caller
responsibilities.

bashlog MAY use Bash-native current-time facilities if the project decides that
standard timestamp generation belongs to logging.  Such use does not violate the
no-external-command guarantee because no external process is started.  Bash 4.3
already provides builtin `printf` time formatting, so automatic timestamp
formatting does not by itself require raising the runtime floor.

bashlog SHALL NOT provide a built-in syslog integration that invokes the external
`logger` command.  A caller may compose bashlog output with `logger` explicitly.

bashlog SHALL NOT invoke external hashing commands as part of redaction.  Hashing
is not a substitute for holding the information required to locate a plaintext
secret in arbitrary text, and an external hashing process would expand rather
than reduce the runtime trust surface.

## Promises

1. **No external runtime command execution.**  During normal library operation,
   bashlog does not invoke external commands.

2. **No hidden subprocess exceptions.**  The guarantee applies whether an
   external program would be invoked directly, through command substitution, in
   a pipeline, in a helper function, or after a `command -v` check.

3. **Caller composition does not become library behavior.**  External commands
   explicitly selected by the caller remain caller-owned even when their output
   is passed to bashlog or when bashlog output is passed to them.

4. **Build tooling is separate from runtime.**  External development and release
   dependencies do not become consumer runtime dependencies merely because they
   participate in producing the released artifact.

5. **Runtime capability failures are not repaired by spawning helpers.**  If a
   required behavior cannot be implemented within the accepted Bash contract,
   bashlog fails according to its documented semantics or the architecture is
   reconsidered; it does not silently fall back to an external tool.

## Non-Promises

1. bashlog does not promise that the caller's script uses no external commands.

2. bashlog does not promise that command substitutions used in arguments are
   safe, side-effect free, or free of sensitive-data exposure.  They execute
   before bashlog receives the resulting arguments.

3. bashlog does not claim that avoiding subprocesses creates secure memory or
   isolation from code running in the same Bash interpreter.

4. bashlog does not claim that pure Bash is inherently more secure than every
   possible external implementation.  The decision reduces boundaries and
   dependencies; it is not a universal statement about implementation quality.

5. The guarantee does not apply to project build and release infrastructure.
   Consumers should distinguish runtime dependencies from development tooling.

6. The project does not promise to retain Bash 4.3 forever if a later Bash
   version provides a material correctness, security, readability, or
   auditability improvement that justifies raising the floor through a new ADR.

## Adversary and Failure Model

This decision is intended to reduce exposure to failures and threats associated
with external runtime execution, including:

- PATH differences between hosts;
- missing utilities;
- command behavior differences between operating systems;
- accidental argument disclosure to external processes;
- additional quoting and escaping boundaries;
- environment leakage to child processes;
- unexpected command aliases or functions when external command resolution is
  poorly controlled;
- failures caused by external utility versions;
- redaction logic that appears local but hands unredacted state to a helper;
- accidental filesystem or network activity hidden behind a utility;
- and implementation growth that makes the sensitive path difficult to audit.

The decision does not attempt to defend against malicious same-process Bash code.
Such code can inspect or modify shell variables, replace functions, alter file
descriptors, or otherwise interfere with execution.

It also does not protect against malicious behavior in commands the caller
intentionally invokes.  If a caller runs an external program and passes a secret
to it before bashlog receives a message, that exposure occurred outside the
library boundary.

The model assumes Bash itself is the trusted runtime.  Compromise of the Bash
interpreter, operating system, debugger boundary, kernel, or host administrator
is outside the protection this decision provides.

## Operational Constraints

- Runtime bashlog code MUST NOT invoke external commands.
- Runtime bashlog code MUST NOT use external `date`, `hostname`, `logger`, `sed`,
  `awk`, `grep`, hashing tools, or equivalent helper utilities.
- Runtime behavior MUST be implementable through Bash language facilities and
  builtins within the declared compatibility floor.
- The library MUST NOT use an external command as a hidden fallback when a
  Bash-native path fails.
- Caller-invoked commands MUST remain outside bashlog's responsibility boundary.
- Build, test, documentation, dependency, and release tooling MAY use external
  commands because those workflows are outside the consumer runtime contract.
- Tests SHOULD include a constrained environment proving representative runtime
  behavior succeeds without access to ordinary external commands.
- Any proposal to add an external runtime integration MUST require a new ADR that
  explicitly supersedes this decision.

## Considered Alternatives

### Permit a Small Allowlist of External Utilities

An allowlist containing tools such as `date`, `hostname`, and `logger` would make
some logging features convenient while still preventing arbitrary command
execution.

It was rejected because each allowed program becomes another runtime dependency
and another data boundary.  Bash already provides enough functionality for the
core logging path, and callers can compose external integrations explicitly.

### Use `logger` for Built-In Syslog Support

The older logging implementation used the `logger` command when configured for
syslog.

This was rejected because it would require external command discovery and hand a
message to another process.  Syslog support is useful, but it can be composed by
the application after bashlog has performed redaction and rendering.

### Use External Text Utilities for Redaction

Tools such as `sed`, `awk`, or Perl could make some substitution algorithms
shorter.

They were rejected because the redaction path is the last place the project
should casually introduce additional process boundaries.  The security benefit
of redaction is stronger when unredacted values remain inside the current Bash
process and are not intentionally transmitted to helper programs.

### Use External Hashing to Avoid Plaintext Redaction State

Hashing registered secrets may initially appear to reduce the sensitivity of
internal state.

It was rejected for two independent reasons.  First, a digest does not identify
the location of its plaintext preimage inside an arbitrary message, so generic
redaction would require generating candidate substrings and hashing them.  That
is impractical and does not solve low-entropy guessing concerns.  Second, Bash
does not provide native SHA-256 at the current floor, so this approach would
introduce an external process into the redaction path.

### Require the Caller to Supply All Metadata, Including Time

A strict interpretation of caller-owned acquisition would require the caller to
supply even timestamps.

This remains a viable design style, but it is not required by the no-external-
command boundary because Bash can format current time using builtin facilities.
Whether bashlog supplies standard timestamps is therefore a logging-policy
question rather than a runtime-purity question.

## Consequences

The consumer runtime dependency surface is exceptionally small: Bash itself is
the relevant executable dependency.

Some integrations will require a small amount of caller composition.  That is an
accepted cost and often an architectural advantage because the caller explicitly
owns the boundary where data leaves bashlog.

Implementation may occasionally be longer than an equivalent pipeline using
specialized text-processing utilities.  Readability remains a separate binding
constraint: pure Bash is not permission to implement opaque shell gymnastics.
If a required behavior cannot be expressed correctly and audibly within the
current Bash floor, the project should reconsider the runtime floor or the
feature rather than sacrifice clarity.

## Source Lineage

This decision is influenced by:

- mktext's narrow caller/library responsibility boundary;
- bashdeps' explicit acquisition and trust boundaries;
- the older shell logging implementation, which demonstrates useful behavior but
  also shows how external `date`, `hostname`, `logger`, and `sed` dependencies can
  enter a logging path;
- and the project's redaction design discussion, where minimizing exposure of
  unredacted data became a first-class security goal.

## Open Questions and Follow-Ups

- Whether standard timestamps are enabled by default, opt-in, or caller-supplied
  remains a logging-format decision.
- The redaction feasibility work must verify that fixed, glob, and ERE matching
  can meet the project's correctness and readability requirements at Bash 4.3.
- Bash 5.2 should be reconsidered if it materially reduces dangerous array-
  subscript semantics or makes the security-critical path substantially clearer.
- The final test plan should define how the no-external-command invariant is
  demonstrated without conflating Bats/test-harness commands with library
  runtime behavior.

## Related Decisions

- ADR-002: Bash Runtime and Portability Baseline
- ADR-005: Dependency Management and Explicit Network Boundaries
- ADR-013: Sourceable Library Scope and Responsibility Boundary
- ADR-018: Redaction as an Opt-In Security Boundary
- ADR-019: Readability, Auditability, and Rejection of Obscurity
