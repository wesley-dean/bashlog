# ADR-016: Modular Source Assembly for a Sourceable Library

Date: 2026-08-30

## Status

Accepted

## Intent and Documentation Posture

This ADR adapts the modular source architecture inherited from template-bash to
the needs of a sourceable logging library.

The project intentionally retains the strongest parts of the template pattern:
small maintained source files, explicit ordering for core dependencies,
deterministic discovery for additive modules, and standalone generated consumer
artifacts.  It intentionally rejects the starter's command-oriented runtime
plugin registry because bashlog's higher-level modules are functions composed
into a library, not commands selected through a runtime dispatcher.

The distinction is important.  The word "plugin" can describe many forms of
extension.  In bashlog, modularity is primarily a **maintenance and assembly
architecture**, not a runtime dynamic-loading system.

## Context

template-bash established an architecture in which maintained implementation is
split between explicitly ordered core files and lexically discovered files under
`lib/plugins/`.  Each starter plugin registers a logical name and implementation
function with a runtime registry, after which the generated CLI can dispatch to
that plugin by name.

That design is appropriate for the starter's example command interface.  bashlog
has different runtime needs.

A consumer is expected to source a generated library artifact and invoke named
Bash functions directly:

```bash
bashlog_info 'starting'
bashlog_error 'failed'
```

There is no need to translate `info` into a registry lookup that then resolves a
function name.  The function itself is already the public interface.

At the same time, the separation between lower-level core behavior and
higher-level convenience behavior remains useful.  For example, a `die` helper
is naturally built on logging primitives and process termination.  It is more
application-facing and policy-heavy than a low-level formatter or redactor.
Keeping those concerns in separate maintained files makes the source easier to
review without requiring consumers to source a directory full of fragments.

The project also wants a single-file distribution model because bashdeps treats
the released artifact as ordinary pinned bytes.  Consumers should not need to
reproduce bashlog's maintainer source tree to use the library.

## Decision Drivers

- Keep security-sensitive core behavior small and reviewable.
- Preserve explicit dependency ordering among core modules.
- Allow higher-level modules to be added without turning one file into a large
  collection of unrelated helpers.
- Avoid unnecessary runtime dispatch, registries, reflection, or indirection.
- Produce standalone artifacts suitable for bashdeps acquisition.
- Preserve deterministic, inspectable builds.
- Keep module boundaries meaningful to maintainers without imposing those
  boundaries as runtime filesystem requirements on consumers.
- Avoid runtime sourcing of arbitrary plugin directories.
- Preserve the template-bash build architecture where it provides value while
  intentionally removing starter behavior that does not fit the derived project.

## Decision

bashlog SHALL maintain its implementation as modular Bash source assembled into
standalone distribution artifacts at build time.

Core modules SHALL be listed in an explicit build order.  Core ordering is an
architectural dependency and MUST remain visible in the Makefile or equivalent
canonical build source rather than being inferred dynamically.

Representative core responsibilities are expected to include areas such as:

```text
context / configuration
log levels
redaction
formatting
emission
```

The exact filenames and boundaries may evolve as implementation work reveals the
cleanest decomposition.  This ADR does not require one file per word in the list.
It requires that security-sensitive responsibilities remain deliberately
organized and that ordering dependencies remain explicit.

Higher-level convenience modules MAY live under `lib/plugins/` and MAY continue
to be discovered automatically at build time in deterministic lexical pathname
order.

For bashlog, a file under `lib/plugins/` SHALL mean an additive build-time module
whose functions are assembled into the released library.  Such modules SHALL NOT
be required to register themselves with a runtime plugin registry merely to make
their functions callable.

bashlog SHALL remove the inherited starter runtime plugin registry unless a
future, separately justified extension point requires runtime registration for a
specific reason.

The inherited noop plugin SHALL be removed.  It is useful starter behavior but is
not part of bashlog's domain.

Generated artifacts SHALL contain the assembled core and selected project
modules and SHALL NOT require the source tree, `lib/plugins/`, or `vendor/` at
consumer runtime.

Plugin/module source discovery SHALL occur during the build, not while the
consumer sources bashlog.

Maintained Bash source paths participating in Make-based source lists SHALL
remain whitespace-free.  This preserves the transparent source-discovery and
assembly contract inherited from the template.

Lexical order among additive modules SHALL be deterministic, but peer modules
SHOULD NOT rely on incidental lexical ordering for semantic dependencies.  If
one module must exist before another for correctness, that dependency should be
made architecturally explicit rather than encoded through filename tricks.

A higher-level module MAY depend on stable core functions.  A core security
primitive MUST NOT depend on a convenience module merely because that module is
discovered later.

## Promises

1. **Maintainer modularity, consumer simplicity.**  Maintainers work with small,
   responsibility-focused source files while consumers receive a standalone
   artifact.

2. **Core order is explicit.**  Dependencies among core modules are visible and
   reviewable rather than inferred from filesystem order.

3. **Additive modules are deterministic.**  Automatically discovered modules are
   assembled in a repeatable lexical order.

4. **No runtime plugin machinery is required for ordinary logging functions.**
   A function assembled into the artifact is callable as a Bash function without
   registry lookup or dynamic dispatch.

5. **No runtime source-tree dependency.**  A released artifact does not need to
   locate `lib/`, `lib/plugins/`, or `vendor/` after publication.

6. **No automatic runtime discovery.**  Sourcing bashlog does not scan directories
   or source arbitrary plugin files from the host.

## Non-Promises

1. The presence of a file under `lib/plugins/` does not imply runtime
   installability, hot loading, or third-party extension discovery.

2. The lexical discovery mechanism does not promise that arbitrary modules may
   depend on one another through filename order.  Semantic dependencies must be
   made explicit.

3. The term "plugin" does not guarantee a stable third-party plugin API.  In the
   initial architecture it primarily denotes an additive maintained module.

4. Modular maintained source does not imply multiple runtime files.  The release
   contract remains single-artifact consumption.

5. Automatic build discovery does not authorize runtime metaprogramming or
   dynamic function generation.

## Adversary and Failure Model

This decision addresses maintenance and assembly failures such as:

- a monolithic source file becoming difficult to review;
- security-sensitive helpers being mixed with application-facing conveniences;
- adding a convenience function requiring edits to an unrelated runtime
  dispatcher;
- generated artifacts depending accidentally on maintainer filesystem layout;
- nondeterministic build ordering;
- hidden semantic dependencies encoded in filesystem discovery;
- runtime directory scanning that could source unexpected code;
- and retaining starter-only registry/noop behavior because it happened to exist
  in the template.

The design assumes the repository's maintained source and build inputs are
trusted project source.  It does not attempt to treat `lib/plugins/` as an
untrusted third-party plugin marketplace.

The design does not defend against malicious code intentionally committed as a
maintained module.  Code review, repository protections, tests, and supply-chain
controls govern trusted source changes.

## Operational Constraints

- Core source files MUST have an explicit deterministic assembly order.
- Additive module files MAY be automatically discovered under `lib/plugins/` in
  lexical pathname order.
- Additive modules MUST NOT require a runtime registry merely to expose ordinary
  Bash functions.
- The inherited template plugin registry SHOULD be removed from bashlog.
- The inherited noop plugin MUST be removed.
- Runtime library loading MUST NOT discover or source module files from the
  consumer filesystem.
- Generated artifacts MUST be standalone and MUST NOT depend on `lib/`,
  `lib/plugins/`, or `vendor/` at runtime.
- Maintained source filenames used in Make lists MUST remain whitespace-free.
- Semantic dependencies among modules MUST NOT rely solely on incidental lexical
  peer ordering.
- Security-sensitive core modules MUST NOT depend on higher-level convenience
  modules.

## Considered Alternatives

### Keep the Template Runtime Plugin Registry

Keeping the registry would minimize changes to the starter architecture and
would provide a generic extension mechanism.

It was rejected because bashlog does not need command-name-to-function dispatch
for ordinary logging calls.  A registry would add state, indirection, public
functions, and documentation without solving a real runtime requirement.

### Put Everything in One Maintained Source File

A monolithic file would closely resemble the single artifact consumers receive
and would remove assembly machinery.

It was rejected because maintained-source readability matters more than making
the source tree mimic the distribution representation.  Security-sensitive
redaction code, log-level policy, formatting, and application-facing helpers are
easier to reason about when responsibilities are separated.

### Ship Every Module as a Separate Runtime File

Consumers could source only the modules they want.

It was rejected as the default because it complicates dependency acquisition,
ordering, version compatibility, and deployment.  bashdeps is particularly well
suited to acquiring one reviewed and digest-pinned artifact.

### Dynamically Source Plugins at Runtime

A runtime plugin directory could allow consumers to extend bashlog without
rebuilding it.

It was rejected because it would make behavior depend on host filesystem state,
introduce loading policy into a logging library, complicate the trust model, and
conflict with the source-time side-effect constraints.

### Enumerate Every Convenience Module Explicitly

This would make all source order completely explicit.

It remains viable, but automatic deterministic discovery is useful for truly
additive leaf modules and is already well supported by the template.  The
architecture therefore retains explicit ordering for core and lexical discovery
for additive modules.

## Consequences

The project will retain a `lib/plugins/` concept but change what that concept
means relative to the starter.  Maintainers must not assume the template's
runtime registration semantics continue to apply.

The Makefile becomes an architectural map of core dependencies.  Changes to core
ordering deserve review because they can change behavior even when individual
files do not.

The generated development artifact remains an especially useful audit surface:
it shows the complete assembled library, in the exact order consumers receive,
while retaining the verbose Doxygen commentary from the maintained modules.

## Source Lineage

This decision adapts template-bash ADR-004 and draws from Bootstrap's modular
source assembly.  It preserves:

- explicit core source ordering;
- deterministic build assembly;
- whitespace-free maintained source paths;
- automatic discovery where extension is genuinely additive;
- and standalone generated artifacts.

It rejects the portions of the template decision that exist specifically for the
starter's command-oriented plugin example: the runtime registry and noop plugin.

## Superseded Decisions

This ADR supersedes ADR-004 for bashlog where ADR-004 requires:

- plugin registration through the starter runtime registry;
- runtime dispatch by registered plugin name;
- and retention of the noop reference plugin.

ADR-004 remains in force for the principles of modular maintained source,
explicit core ordering, deterministic lexical discovery of additive modules,
whitespace-free source paths, and standalone generated artifacts.

## Open Questions and Follow-Ups

- The first implementation plan should propose concrete core module boundaries
  after the foundational ADRs are accepted.
- The project still needs to decide whether `die` is assembled into the default
  artifact or offered through an optional convenience artifact.
- If third-party runtime plugins are ever proposed, they require a new ADR because
  this decision explicitly does not establish such an extension mechanism.

## Related Decisions

- ADR-004: Modular Source Assembly and Automatically Discovered Plugins
- ADR-006: Three Release Artifact Flavors, Metadata, and Checksums
- ADR-013: Sourceable Library Scope and Responsibility Boundary
- ADR-015: Namespaced Public API and Caller-Owned Convenience Wrappers
- ADR-019: Readability, Auditability, and Rejection of Obscurity
