# ADR-015: Namespaced Public API and Caller-Owned Convenience Wrappers

Date: 2026-08-30

## Status

Proposed

## Intent and Documentation Posture

This ADR defines how bashlog exposes callable functions to consumers and how the
project balances collision-resistant library names with readable application
code.

The decision is intentionally explicit because Bash has no package namespace,
module import declaration, private function visibility, or language-level symbol
isolation.  Every sourced function enters the caller's shell namespace.  A
library that publishes generic names therefore competes directly with functions,
aliases, and conventions defined by the application and every other sourced
library.

The project wants readable caller code.  It also wants loading bashlog to be
predictable and non-invasive.  The solution is to separate the stable namespaced
public API from optional convenience names selected by the application.

## Context

Logging calls are often most readable when they are short:

```bash
info 'Starting migration'
warn 'Configuration is deprecated'
error 'Database connection failed'
die 'Cannot continue'
```

Those names are attractive precisely because they are generic.  That also makes
them poor unconditional exports from a reusable library.

Bash offers several mechanisms that can superficially resemble importing or
aliasing library functions:

- aliases;
- exported functions;
- dynamically generated wrapper functions;
- `eval`;
- indirect dispatch through registries;
- explicitly written wrapper functions.

These mechanisms do not have equal behavior or equal auditability.

Aliases are particularly unsuitable as a library import mechanism.  In
non-interactive Bash, aliases are not expanded unless `expand_aliases` is enabled,
and alias expansion occurs while commands are parsed rather than behaving like a
normal function call.  A library should not change the caller's `shopt` settings
merely to make its preferred convenience mechanism work.

Exported functions solve a different problem: making a function available to
child Bash processes through the environment.  bashlog does not need to push its
API across process boundaries merely to make local calls shorter.

Dynamic generation through `eval` or metaprogramming would make the public
surface harder to inspect and would conflict with the project's explicit
readability and auditability goals.

Ordinary wrapper functions, by contrast, have straightforward Bash semantics:

```bash
warn() {
  bashlog_warn "$@"
}
```

The caller can see exactly what name is being claimed and exactly which stable
library function it delegates to.

## Decision Drivers

- Avoid collisions with caller functions, aliases, and other libraries.
- Keep the stable public API discoverable and greppable.
- Preserve readable application code when the caller explicitly wants short
  names.
- Avoid changing `shopt` state or relying on alias expansion.
- Avoid `eval`, dynamic function generation, and hidden metaprogramming.
- Avoid exporting library functions into child-process environments by default.
- Keep internal implementation details distinct from supported public entry
  points.
- Make examples understandable to developers with ordinary Bash experience.
- Preserve future freedom to refactor internals without breaking documented
  public names.

## Decision

bashlog SHALL expose its supported public API through functions using a stable,
project-specific namespace.

The initial namespace SHALL use the `bashlog_` prefix unless a later ADR changes
the public naming convention before a stable release.

Representative public names may include:

```text
bashlog_debug
bashlog_info
bashlog_warn
bashlog_error
bashlog_die
bashlog_redact
```

The exact final inventory and signatures belong to the normative project
specification and more focused ADRs.  This ADR establishes the naming model, not
every function that must exist.

Internal implementation helpers SHALL use a visibly distinct internal naming
convention, expected to use `__bashlog_` as a prefix.  The double underscore is a
human-readable convention indicating implementation detail.  It does not create
privacy or access control, and project documentation MUST NOT describe it as
language-enforced privacy.

Public convenience functions such as `bashlog_warn` SHALL call stable public or
internal behavior according to a documented architecture.  Application-level
short names SHALL delegate to stable namespaced public functions rather than
calling `__bashlog_*` internals directly.

bashlog SHALL NOT automatically define generic functions named `debug`, `info`,
`warn`, `warning`, `error`, `die`, or equivalent convenience names merely when
the core library is sourced.

The project documentation SHALL show callers how to create explicit wrapper
functions when short names improve readability.  For example:

```bash
info() {
  bashlog_info "$@"
}

warn() {
  bashlog_warn "$@"
}

error() {
  bashlog_error "$@"
}

die() {
  bashlog_die "$@"
}
```

Such wrappers are application policy.  The caller owns the generic names and the
risk of collisions.

The repository MAY also ship an optional convenience source module containing
explicit wrapper definitions if that module can be included without making the
core source operation invasive.  If provided, inclusion of those wrappers MUST
be an explicit consumer choice, MUST be implemented as ordinary functions, and
MUST NOT rely on aliases, `eval`, dynamic function generation, or `export -f`.

Whether optional short-name wrappers are distributed as a separate released
artifact, an optional source file, or documentation-only examples remains open
until the artifact model is examined more closely.  The core namespaced API does
not depend on that decision.

bashlog SHALL NOT use aliases as its supported convenience API.

bashlog SHALL NOT enable `expand_aliases` on behalf of callers.

bashlog SHALL NOT use `export -f` for ordinary API exposure.

bashlog SHALL NOT generate API wrapper functions through `eval` or equivalent
runtime code construction.

## Promises

1. **Stable namespaced public surface.**  Supported bashlog functions use an
   explicit project namespace rather than silently occupying generic application
   names.

2. **Internal names remain visibly internal.**  Implementation helpers are
   distinguishable from the supported public API, and documentation does not ask
   callers to depend on them.

3. **No alias magic.**  Consumers do not need `expand_aliases`, parse-time alias
   behavior, or shell-option mutation to use bashlog.

4. **Readable wrappers remain available.**  Applications can intentionally create
   short wrapper functions that delegate to stable bashlog public functions.

5. **No dynamic import machinery.**  The convenience model remains ordinary Bash
   code that can be inspected without reconstructing generated functions.

6. **No automatic function export to children.**  Sourcing bashlog does not use
   `export -f` to place its functions into child Bash environments.

## Non-Promises

1. The `bashlog_` prefix does not provide cryptographic isolation or prevent a
   caller from intentionally redefining a bashlog function.

2. The `__bashlog_` prefix does not make implementation state private.  Bash does
   not provide private functions or private variables between code executing in
   the same shell process.

3. bashlog does not guarantee that caller-created wrappers are collision free.
   Choosing a generic application name is explicitly the caller's decision.

4. bashlog does not promise that every example in application code must use the
   full namespaced form.  Documentation may show wrappers where doing so improves
   readability, provided the ownership boundary is clear.

5. bashlog does not promise that internal helper names remain stable across
   releases.  Only documented public interfaces participate in compatibility
   guarantees.

## Adversary and Failure Model

This decision primarily addresses accidental namespace collision and hidden shell
semantics rather than malicious same-process code.

The model accounts for:

- applications that already define `info`, `warn`, `error`, or `die`;
- multiple sourced libraries with overlapping generic names;
- non-interactive shells where aliases are not expanded by default;
- maintainers who might otherwise enable `expand_aliases` globally for library
  convenience;
- callers who need short, readable logging calls;
- refactoring of implementation helpers beneath a stable public API;
- accidental coupling of consumer code to internal function names;
- convenience mechanisms that would be difficult to understand because they use
  `eval` or generated definitions.

The model does not defend against hostile same-process code that intentionally
redefines `bashlog_info`, unsets library functions, modifies library variables,
or otherwise interferes with the process.  Bash does not provide a meaningful
symbol-isolation boundary for such code.

The model also does not prevent a caller from deliberately exporting wrapper
functions or bashlog functions to child Bash processes.  It only states that
bashlog itself does not do so as part of normal loading.

## Operational Constraints

- Supported public functions MUST use the documented bashlog namespace.
- Internal functions SHOULD use a distinct `__bashlog_` prefix or a successor
  convention established by ADR.
- Documentation MUST NOT describe `__bashlog_*` functions or variables as truly
  private or access-controlled.
- Core library sourcing MUST NOT define generic convenience functions.
- Core library sourcing MUST NOT define aliases.
- bashlog MUST NOT enable `expand_aliases`.
- bashlog MUST NOT use `export -f` for ordinary API exposure.
- bashlog MUST NOT use `eval` or dynamic function generation to implement short
  names or imports.
- Documentation SHOULD demonstrate explicit wrapper functions for callers that
  want short names.
- Caller wrappers MUST delegate to stable namespaced public functions in project
  examples; examples SHOULD NOT teach consumers to call `__bashlog_*` internals.
- Any optional short-name module MUST be explicitly opted into and MUST use
  ordinary wrapper functions.

## Considered Alternatives

### Export Generic Function Names From the Core

This would produce the most concise application code immediately after sourcing
the library.

It was rejected because names such as `info`, `warn`, `error`, and `die` are too
generic for a reusable Bash library to claim unconditionally.  Collision risk is
not theoretical in a language with a single sourced function namespace.

### Use Bash Aliases

Aliases can make `warn` expand to a namespaced function name with very little
code.

They were rejected because alias expansion semantics differ from ordinary
function calls, are disabled by default in non-interactive shells, and would
create pressure for bashlog to change `shopt` state.  They are also less obvious
when reading function-oriented application code.

### Export Functions With `export -f`

Exported functions would make bashlog helpers available to child Bash processes.

It was rejected because that behavior is unnecessary for ordinary sourceable
library use and crosses a process/environment boundary without solving the
namespace problem in the current shell.

### Generate Wrappers Dynamically

A list of convenience names could be looped over and converted into functions
using `eval` or generated declarations.

It was rejected because the small reduction in repeated source text is not worth
making the public interface harder to audit.  Explicit wrapper definitions are
short, readable, searchable, and unsurprising.

### Have Short Wrappers Call Internal Functions Directly

If `warn()` simply delegates to `__bashlog_log`, there may be one fewer public
layer.

It was rejected because it couples caller convenience code to implementation
details.  A stable namespaced public layer allows internals to evolve without
requiring applications to rewrite their wrappers.

### Encode or Obfuscate Internal Names

Unusual names could make accidental collisions less likely and make internals
less obvious to callers.

It was rejected because obscurity is contrary to bashlog's trust model.  Internal
state should be plainly named and easy to inspect.  Namespace discipline should
be achieved through clear naming, not deliberate opacity.

## Consequences

Application examples that use the raw API will be slightly more verbose than
examples based on generic logging names.

That verbosity is a library-boundary cost, not an application requirement.  A
caller that values shorter names can establish them explicitly in a few lines of
ordinary Bash.

The project gains a public surface that is easier to document, search, test, and
preserve across refactors.  It also avoids having library loading depend on
parse-time alias behavior or global shell configuration.

The distinction between `bashlog_*` and `__bashlog_*` should make source review
clearer, but maintainers must remain honest that the distinction is conventional,
not an isolation mechanism.

## Source Lineage

This decision draws from:

- the namespacing patterns used across Bootstrap, bashdeps, mktext, adrctl, and
  related Bash projects;
- the earlier discussion of importing or exporting logging convenience names;
- bashlog's source-time side-effect constraints in ADR-013;
- and the project's broader requirement that security-sensitive code remain
  explicit rather than relying on hidden language behavior.

## Open Questions and Follow-Ups

- Decide whether optional short-name wrappers should be documentation-only or
  shipped as a separately consumable artifact/module.
- Decide the exact initial public severity-function inventory.
- Decide whether `bashlog_warning` and `bashlog_warn` are aliases in the public
  API, or whether only one spelling is supported.
- Decide whether `bashlog_die` belongs in the default assembled artifact or an
  optional convenience layer.
- The future project specification should identify which public names carry
  semantic-version compatibility guarantees.

## Related Decisions

- ADR-013: Sourceable Library Scope and Responsibility Boundary
- ADR-016: Modular Source Assembly for a Sourceable Library
- ADR-017: Logging Levels, Formatting, and Emission Model
- ADR-019: Readability, Auditability, and Rejection of Obscurity
