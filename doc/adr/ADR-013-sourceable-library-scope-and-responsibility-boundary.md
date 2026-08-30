# ADR-013: Sourceable Library Scope and Responsibility Boundary

Date: 2026-08-30

## Status

Proposed

## Intent and Documentation Posture

This Architecture Decision Record establishes the fundamental scope of bashlog
and the boundary between responsibilities owned by the library and
responsibilities retained by its callers.

This decision is intentionally detailed.  bashlog will provide logging and
redaction behavior that may be trusted with sensitive values.  That trust must
not depend on vague expectations about what a logging library might do.  The
project therefore documents both the capabilities it intentionally provides and
the capabilities it deliberately refuses to assume.

The reasoning is part of the decision.  Future maintainers should not need to
reverse-engineer the original design conversation from implementation details,
removed code, or the behavior of older projects from which some ideas were
learned.

## Context

The project originates from useful logging behavior that previously existed
inside a broader Bash support library.  That older library also contained module
loading, dependency checks, stack-trace helpers, global shell-policy decisions,
and automatic error trapping.  Those concerns made sense within the role that
library had accumulated, but they are not all part of logging.

bashlog is being created as a deliberately narrower component.  It should provide
logging, log-level behavior, formatting, emission, and explicit redaction without
becoming an application framework or a general-purpose shell utility library.

The intended consumer model is also different from a standalone application.
bashlog is expected to be acquired as a pinned artifact, commonly through
bashdeps, and sourced into another Bash process.  The consumer remains the
application.  bashlog is a library inside that application.

That distinction matters because sourcing a Bash file occurs in the caller's
shell process.  A sourceable library is capable of changing shell options,
installing traps, defining generic names, changing `shopt` settings, mutating the
working directory, changing positional parameters indirectly, exporting state,
or performing other actions that alter the caller's execution environment.
Those actions may be technically possible, but they are inappropriate as hidden
side effects of loading this library.

The library should also preserve a clear ownership boundary for message data.
Callers may choose to obtain dates, Git revisions, host information, UUIDs,
network-derived values, configuration values, or other data before invoking a
logging function.  bashlog should not grow into a general acquisition layer for
those values merely because they sometimes appear in log messages.

The same separation applies to external integrations.  A caller may intentionally
send already-redacted text to syslog, a remote service, a file processor, or
another external program.  That integration does not make the external tool a
bashlog responsibility.

The project therefore needs a foundational statement answering three questions:

1. What does bashlog own?
2. What does the caller continue to own?
3. What side effects are forbidden merely as a consequence of sourcing the
   library?

## Decision Drivers

- Keep bashlog small enough that its security-sensitive behavior can be audited.
- Preserve a clear separation between logging and application control flow.
- Avoid source-time surprises in the caller's shell.
- Support bashdeps-style consumption as a standalone sourceable artifact.
- Prevent legacy behavior from the older shell support library from becoming an
  accidental requirement.
- Allow callers to compose bashlog with external commands without making those
  commands dependencies of the library.
- Keep acquisition and transformation of application data under application
  control.
- Make the security boundary legible to developers with ordinary Bash skills.
- Avoid turning convenience features into hidden global policy.

## Decision

bashlog SHALL be a sourceable Bash logging library whose core responsibilities
are limited to logging-related behavior.

The library MAY provide:

- log-level and severity handling;
- message formatting;
- output formatting;
- configured logging metadata that can be produced within the accepted runtime
  boundary;
- logging sinks that can be implemented using Bash facilities within the library
  contract;
- explicit sensitive-value redaction;
- validation of logging and redaction configuration;
- namespaced logging convenience functions built on the common logging pipeline;
- and narrowly scoped helpers, such as a `die`-style function, when the helper is
  explicitly invoked by the caller and is implemented as composition over the
  logging API.

The library SHALL NOT become responsible for general-purpose module loading,
remote code acquisition, package installation, dependency discovery, arbitrary
command execution, or application lifecycle management.

The caller SHALL retain ownership of application data acquisition and
application-specific transformation.  A caller that wants a log message to
contain the output of `date`, `git`, `hostname`, `uuidgen`, an HTTP client, a
configuration program, or any other external command is responsible for invoking
that command and passing the resulting string to bashlog.

The library MAY use Bash-native facilities for logging metadata when a separate
ADR explicitly defines that behavior.  The existence of Bash-native metadata
facilities does not grant the library open-ended authority to inspect the host or
application environment.

The library SHALL NOT automatically install an `ERR` trap or any other trap.
Logging an error and deciding what application execution should do after that
error are separate responsibilities.

The library MAY provide an explicitly invoked `bashlog_die`-style helper that
logs and exits according to a documented contract.  Providing such a helper does
not authorize bashlog to install traps that call it automatically.

Sourcing a released bashlog artifact SHALL be intentionally quiet and minimally
invasive.  Merely sourcing the library SHALL NOT:

- emit a log message;
- intentionally write to standard output or standard error;
- install or replace traps;
- enable or disable shell options with `set`;
- enable or disable `shopt` options;
- change the current working directory;
- create aliases;
- define unnamespaced convenience functions such as `info`, `warn`, `error`, or
  `die`;
- invoke external commands;
- access the network;
- create files or directories;
- export redaction state;
- persist configuration;
- or intentionally alter caller control-flow policy.

The generated distribution artifact SHALL be usable as a sourced library without
depending on the source repository layout or `vendor/` at runtime.

A standalone execution mode MAY exist for narrowly scoped informational behavior
such as `--help` or `--version` if separately documented.  If such a mode exists,
it MUST be explicitly distinguishable from sourced-library behavior and MUST NOT
cause the source path to execute the standalone entrypoint.

## Promises

Subject to the assumptions and limitations documented in this ADR and related
records, bashlog makes the following foundational promises:

1. **Library loading is not application-policy installation.**  Sourcing bashlog
   does not install traps, change shell options, create generic aliases, or take
   ownership of the caller's error-handling strategy.

2. **Logging remains the project scope.**  bashlog does not become a general
   module loader, dependency manager, host-inspection framework, or arbitrary
   command runner merely because those capabilities could be useful near logging
   code.

3. **Caller-prepared data remains caller-owned.**  The caller may gather and
   transform application data however it chooses and then pass the resulting
   text to bashlog.

4. **Sourcing is quiet.**  Loading the library does not itself produce logging
   output or intentionally mutate external state.

5. **Distribution is standalone.**  Consumers can source the released artifact
   without requiring the maintainer's modular source tree at runtime.

6. **Control-flow helpers are explicit.**  If bashlog provides a helper that
   exits, the caller invokes that helper intentionally; the existence of the
   helper does not silently change application control flow.

## Non-Promises

This decision deliberately does not promise the following:

1. bashlog does not guarantee that callers will avoid invoking external commands
   while constructing arguments passed to logging functions.

2. bashlog does not guarantee that caller-provided message data is trustworthy,
   correct, normalized, or safe merely because bashlog receives it.

3. bashlog does not become responsible for side effects that occur before a
   bashlog function is entered.  For example, command substitution is performed
   by Bash before the resulting arguments are passed to the function.

4. bashlog does not replace application-specific exception, retry, recovery,
   shutdown, or process-supervision policy.

5. bashlog does not guarantee that unrelated code sourced into the same shell is
   side-effect free.

6. bashlog does not claim that every useful logging integration must be built
   into the library.  Composition with caller-owned tools is an intended design
   pattern.

## Adversary and Failure Model

This ADR primarily addresses accidental scope expansion, hidden source-time side
effects, and confusion over responsibility.

The design accounts for the following failure and misuse cases:

- a consumer sources bashlog from a script that already has its own `ERR`, `EXIT`,
  `INT`, or other traps;
- a consumer uses `set -e`, `set -u`, `pipefail`, or project-specific shell
  options before loading bashlog;
- an application uses generic helper names that would collide with names such as
  `info`, `warn`, `error`, or `die`;
- a caller uses external commands while constructing a message;
- a caller chooses an external downstream logging integration;
- a maintainer is tempted to move adjacent but non-logging behavior into bashlog
  for convenience;
- a future convenience helper needs to terminate the process but should not
  silently redefine global application policy.

This decision does not attempt to protect a caller from malicious code already
executing in the same Bash process.  A malicious sourced component can change
traps, shell options, functions, variables, file descriptors, and other process
state regardless of bashlog's own discipline.  Protection from hostile
same-process code is outside this ADR's boundary and is addressed more explicitly
in the redaction threat model.

This decision also does not prevent a caller from intentionally wrapping bashlog
with behavior that changes application policy.  For example, a consumer may
write its own `die()` wrapper or install its own `ERR` trap that calls a
namespaced bashlog function.  That is application policy because the application
made the decision explicitly.

## Operational Constraints

- bashlog MUST be sourceable as a standalone released artifact.
- Sourcing bashlog MUST NOT emit logging output.
- Sourcing bashlog MUST NOT install or replace traps.
- Sourcing bashlog MUST NOT change `set` or `shopt` options.
- Sourcing bashlog MUST NOT create generic aliases or unnamespaced convenience
  functions.
- Sourcing bashlog MUST NOT invoke external commands.
- Sourcing bashlog MUST NOT intentionally access the network or filesystem for
  acquisition, persistence, or configuration discovery.
- bashlog MUST NOT include general-purpose module loading or remote code
  acquisition.
- Application data acquisition and application-specific transformation MUST
  remain caller responsibilities.
- An exiting convenience helper MAY exist only as an explicitly invoked public
  function with documented semantics.
- bashlog MUST NOT automatically bind an exiting helper to `ERR` or any other
  trap.
- Released artifacts MUST NOT require the source tree or `vendor/` at runtime.

## Considered Alternatives

### Continue Using the Existing General Shell Support Library

The older shell support library already contains useful logging behavior.  Reuse
would reduce the amount of extraction work required initially.

It was rejected because that library has accumulated responsibilities that bashlog
explicitly does not want: module loading, broad shell policy, error trapping, and
other application-framework behavior.  Removing those concerns conceptually is
part of the reason for creating a dedicated project.

The older implementation remains useful source material.  Its existence does not
make its entire architecture a requirement.

### Install Error Traps Automatically

Automatic installation of `trap 'die' ERR` can produce convenient fail-fast
behavior in a particular application framework.

It was rejected because a sourceable logging library does not own the caller's
error policy.  The caller may already have an `ERR` trap, may intentionally not
use one, or may have recovery semantics incompatible with immediate termination.
A logging dependency should not silently make that choice.

### Provide Generic `info`, `warn`, `error`, and `die` Functions Directly

Short names make application code pleasant to read.

They were rejected as mandatory library exports because these names are common
and collision-prone.  The project will instead use a namespaced public API and
document how applications can create explicit wrappers when desired.  That
separate decision is recorded in ADR-015.

### Add Host Inspection and Metadata Acquisition to the Core

Logging often includes timestamps, hostnames, process details, Git revisions, and
other metadata.  Automatically collecting all of those values would make bashlog
more feature-complete.

It was rejected as a general principle because feature completeness is not the
primary objective.  Each acquisition mechanism expands the runtime surface and
the amount of behavior a reviewer must trust.  Bash-native metadata may be added
when it remains within the runtime boundary and has a clear logging purpose, but
external acquisition belongs to the caller.

### Build External Logging Integrations Into bashlog

Direct syslog or remote-service integrations may be convenient.

They were rejected from the foundational scope because they require external
commands, network behavior, protocol clients, or additional dependencies.
Applications may compose already-redacted bashlog output with those systems under
their own policy.

## Consequences

bashlog will expose fewer automatic conveniences than a broad shell framework.
Applications may need a few lines of wrappers or data acquisition code.

That cost is intentional.  The resulting library has a smaller trust surface,
clearer responsibilities, fewer source-time surprises, and a security-sensitive
path that can be understood without first learning unrelated framework behavior.

The decision also creates pressure to resist future feature requests that are
adjacent to logging but do not belong to logging.  The correct response may often
be documentation showing composition rather than new library code.

## Source Lineage

This decision draws from several established project patterns:

- the earlier `shell_script_library/base.bash` logging implementation, which
  provides useful behavior to extract but also demonstrates the scope that
  bashlog intentionally does not inherit;
- mktext's separation between caller acquisition/transformation and narrow
  library responsibility;
- bashdeps' explicit distinction between acquisition and consumption of a pinned
  artifact;
- Bootstrap's preference for explicit, inspectable component boundaries and
  composition over hidden special cases;
- and the template-bash scaffold's instruction to delete starter behavior that
  does not belong in a derived project.

## Open Questions and Follow-Ups

- The exact set of Bash-native metadata that bashlog may generate, if any, will
  be decided separately from this broad responsibility boundary.
- The exact sink model, including whether caller-provided file descriptors are a
  public feature, remains to be specified.
- The public behavior of `bashlog_die` or equivalent terminating helpers remains
  to be defined in the logging API ADR and specification.
- A future normative `doc/bashlog-spec.md` should translate accepted ADRs into
  precise current behavior after the public API stabilizes.

## Related Decisions

- ADR-000: Capability Scope, Epistemic Honesty, and Separation of Concerns
- ADR-001: Documentation and Decision Hierarchy
- ADR-002: Bash Runtime and Portability Baseline
- ADR-014: Pure Bash Runtime and External Command Boundary
- ADR-015: Namespaced Public API and Caller-Owned Convenience Wrappers
- ADR-016: Modular Source Assembly for a Sourceable Library
- ADR-018: Redaction as an Opt-In Security Boundary
