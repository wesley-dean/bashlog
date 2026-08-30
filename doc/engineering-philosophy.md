# Engineering Philosophy

bashlog's architecture is shaped by a small set of engineering instincts that
recur across its ADRs, public API, tests, and implementation.  This document
collects those instincts in one place so contributors can understand the posture
behind individual decisions without treating this summary as a substitute for the
governing ADRs.

When this document and an Accepted ADR disagree, the ADR governs.  This document
is guidance for areas where the architecture has not already made a more specific
decision.

## Respect Developer Agency

bashlog provides mechanisms without pretending to know application policy better
than the developer who owns the application.

A developer decides what to log, what is sensitive, which redaction rules to
register, when to invoke a redaction context, which severity to assign, and which
presentation settings fit the application.

This is why registering a redaction context does not silently make it ambient and
why a caller may either invoke `bashlog_redact` directly or explicitly pass
`--context CONTEXT` to a logging call.

Strong guarantees begin once the developer deliberately invokes the mechanism.
For example, logger-managed redaction becomes fail-closed after a context is
explicitly selected.  Respecting agency does not mean weakening a security
boundary after the caller has asked bashlog to enforce it.

## Prefer Explicit APIs Over Inference

Important behavior should be visible at the call site or in explicit process-local
configuration.

bashlog therefore prefers:

- `--context CONTEXT` over guessing which redaction policy applies;
- `--tag TAG` over implicit metadata injection;
- `bashlog_format_set`, `bashlog_color_set`, and related setters over deployment
  environment guessing;
- an explicit `--` option terminator over ambiguous positional interpretation;
- canonical severity names over convenience aliases inside the library; and
- bounded symbolic style values over raw ANSI escape strings.

Automatic behavior is appropriate only when the observed property is reliable and
the rule is narrow.  `format=auto` and `color=auto` inspect only whether fd 2 is a
TTY.  They do not infer systemd, Docker, Podman, CI, logging drivers, or operator
intent.

## Follow UNIX Composition Principles Deliberately

UNIX philosophy is a strong influence on bashlog's shape: do one coherent job,
communicate through ordinary interfaces, compose with surrounding tools, and avoid
taking ownership of concerns that belong elsewhere in the pipeline.

For bashlog, that means concrete choices such as:

- routine log records go to stderr so stdout remains available for application
  data, pipelines, and command substitution;
- records remain text rather than requiring a binary transport;
- the library owns logging/redaction behavior while the surrounding environment
  owns persistence, forwarding, aggregation, and service/container integration;
- callers may create ordinary wrappers instead of bashlog claiming generic names
  or application control flow;
- the library exposes sourceable functions rather than forcing a standalone
  command dispatcher;
- exit statuses are part of the documented interface; and
- one standalone generated artifact composes into other Bash projects without
  requiring a runtime framework.

UNIX philosophy is not treated as a slogan that overrides security or correctness.
Fail-closed redaction, process-local configuration, deterministic logfmt, and
standalone generated artifacts are deliberate additions where a stronger contract
is more useful than maximal minimalism.  The relevant question is whether a
mechanism solves a real logging problem without unnecessarily capturing policy or
infrastructure that can remain outside bashlog.

## Treat Every Dependency as New Attack Surface

bashlog is itself a dependency for its consumers, which makes dependency trust a
particularly relevant part of its engineering posture.

A logging dependency can observe data that callers may consider routine until a
credential, token, identifier, private value, or attacker-controlled string passes
through it.  The historical Log4Shell vulnerability in Log4j is a memorable
example of the broader lesson: infrastructure labeled "logging" can still become
a critical attack surface.

The project therefore evaluates dependencies according to authority and data
exposure rather than category names.  For each dependency, ask what code executes,
what data it can see, what ambient privileges or shell state it inherits, what
network/filesystem behavior it can trigger, what transitive code becomes trusted,
and what happens if the dependency is compromised or unavailable.

Pinning and checksums prove that acquired bytes match the reviewed expectation;
they do not prove those bytes are free of vulnerabilities or architecturally
appropriate.

This principle informs bashlog's pure-Bash runtime and deliberately small runtime
surface.  It does not imply that custom code is automatically safer than a
well-reviewed dependency.  It means the comparison should be explicit, with the
trusted computing base treated as a design choice rather than an incidental side
effect of implementation convenience.

Build, test, documentation, and release dependencies remain part of the supply
chain even though they are not present in the consumer runtime artifact.

## Define Contracts Before Mechanisms

Public behavior is a compatibility commitment.  The project therefore prefers to
define what a feature promises, what it does not promise, how it fails, and how it
interacts with existing behavior before optimizing its implementation.

The implementation is allowed to change when the public contract remains true.
Tests are evidence for the contract, not the source of architectural intent.

This distinction matters especially in Bash, where an implementation accident can
easily become de facto API if it is not separated from the intended promise.

## State Promises and Non-Promises

Trust should come from bounded, inspectable claims rather than broad words such as
"secure," "safe," or "automatic."

For consequential behavior, ask both:

- What does bashlog guarantee under the documented assumptions?
- What might a reasonable developer incorrectly assume it guarantees?

The second question is why the documentation explicitly discusses same-process
memory, xtrace, Unicode normalization, embedded NUL, downstream transformations,
and the limits of redaction.

A non-promise is not an excuse for omitting a required property.  If documenting a
non-promise reveals that the property is actually necessary, the design should be
revisited.

## Do Not Manufacture Boundaries the Runtime Does Not Provide

Bash is powerful, but it does not provide private memory between sourced
functions, secure erasure, strong module encapsulation, or a universal native
logging transport abstraction.

bashlog does not disguise ordinary variables and call them private, encode secrets
and call them protected, or infer that stderr is attached to a particular logging
system.

When the runtime cannot honestly support a stronger claim, the project documents
the limitation and designs around the boundary that actually exists.

## Readability and Auditability Are Correctness Properties

Security-sensitive Bash should be understandable by reading the maintained
source.

Prefer:

- plain variable and function names;
- explicit arrays and state transitions;
- visible source ordering;
- ordinary control flow;
- narrow helper functions;
- exact Doxygen contracts beside implementation; and
- bounded algorithms whose termination and failure behavior can be explained.

Avoid `eval`, generated function bodies, reversible obscurity, dynamic variable
name tricks, or metaprogramming whose main benefit is cleverness or apparent
encapsulation.

A reviewer should not need to execute the code mentally as a puzzle before they
can evaluate whether sensitive data can reach a sink.

## Modularity Is Primarily a Maintenance Property

Maintainers benefit from small files organized by responsibility; consumers often
benefit from one standalone artifact.

Those goals are compatible.  bashlog keeps explicit core source ordering and
responsibility-focused modules in the repository while building standalone
consumer artifacts.

Modularity does not automatically imply a runtime plugin registry, dynamic
loading, filesystem discovery, or third-party extension API.  Add indirection
only when the runtime problem actually requires it.

Semantic dependencies should be explicit.  Do not encode correctness through
incidental lexical filenames merely because build-time discovery exists.

## Keep the Public Surface Conservative

Every public function, option, accepted token, output format, and return status
becomes something consumers may depend upon.

Expose a capability because callers need it, not because an internal helper already
exists.  Caller-owned wrappers are often better than library-owned convenience
functions when the behavior represents application policy.

This is why bashlog does not own generic `info`, `warn`, `error`, or `die`
functions even though callers can create those wrappers easily.

## Separate Semantics From Presentation and Transport

Severity, redaction policy, semantic message data, presentation, and transport are
different concerns.

Severity controls filtering independently of whether its human signifier is red,
green, bold, dim, or completely unstyled.  Redaction protects semantic caller data
before renderer escaping.  Human and logfmt serializers present the record.
Standard error is the transport boundary, while the surrounding environment owns
persistence and forwarding.

Keeping these layers separate prevents presentation details from silently changing
security semantics and prevents deployment assumptions from leaking into a small
logging library.

## Fail Closed When a Security Boundary Is Explicitly Invoked

Developer agency determines whether a redaction context is selected.  Once it is
selected, bashlog takes responsibility for honoring it.

Uncertainty at that boundary should suppress protected output rather than silently
fall back to unredacted logging.  This applies to unavailable contexts,
transformation failures, verification failures, and completed records that still
match the selected policy.

Fail-closed behavior is intentionally scoped.  bashlog does not apply unrelated
registered contexts to ordinary logging calls that did not request redaction.

## Prefer Durable Invariants Over Mutable Snapshots

Documentation should describe properties that are intended to remain true rather
than incidental counts or implementation snapshots that will predictably rot.

For example, the important testing guarantee is that every shipped artifact runs
the complete contract suite.  The exact number of tests at one point in time is
useful CI output, but it is not a durable architectural promise.

The same principle applies to generated documentation, build artifacts, and
internal layouts: document exact details when they are contractual; otherwise
document the invariant that matters.

## Treat Generated Artifacts as Products

Consumers source generated bashlog artifacts, not the maintainer's source tree.
Therefore development, ordinary, and minified artifacts are all product surfaces
and must satisfy the same observable contract.

Build assembly, comment stripping, and minification are not assumed harmless merely
because they are build steps.  The exact generated forms are tested.

## Make External and Network Boundaries Visible

Runtime bashlog invokes no external commands.  Development and release tooling may
use them.

Likewise, dependency synchronization may use the network while ordinary build and
verification consume prepared state offline.

A boundary is easier to reason about when the command or phase that may cross it
is explicit.

## Preserve Portability Deliberately

Bash 4.3 is an accepted compatibility floor, not an accident of current syntax.
Newer language features should be adopted when their correctness, security,
readability, or maintainability benefits justify reconsidering that promise.

Compatibility tests should exercise representative behavior, not only syntax.
When the floor becomes genuinely harmful, change the decision explicitly rather
than hiding version-dependent behavior inside clever compatibility code.

## Documentation Is Part of the Architecture

The project deliberately uses different documents for different jobs:

- README for public orientation;
- this document for engineering posture;
- `doc/decisions.md` for concise architectural discovery;
- ADRs for durable reasoning;
- `doc/bashlog-spec.md` for normative observable behavior;
- Doxygen comments for implementation contracts; and
- tests for executable evidence.

Keeping those roles distinct reduces duplication while preserving enough context
to understand both what bashlog does and why it has its current shape.
