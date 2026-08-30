# ADR-001: Documentation and Decision Hierarchy

Date: 2026-08-19

## Status

Accepted

## Intent and Documentation Posture

This ADR defines how the repository preserves architectural reasoning and how
that reasoning is translated into concise operational guidance.  The decision is
intentionally explicit because AI-assisted development makes it increasingly
possible to produce locally plausible changes that are inconsistent with prior
architectural intent.

The repository therefore needs more than accurate implementation.  It needs a
recoverable chain from intent, to constraints, to implementation, to validation.

bashlog strengthens the inherited documentation model by adding
`doc/decisions.md`: a concise decision map containing one-to-three-sentence
summaries of ADR decisions with direct references to the full records.  The
summary exists to make architectural constraints easy to discover; it does not
replace the reasoning preserved in ADRs.

The project intentionally follows a "more is more" posture where additional
documentation preserves context, assumptions, boundaries, rejected alternatives,
trust claims, failure semantics, or reasoning that a future maintainer would
otherwise have to reconstruct.

## Context

The Bash projects that informed this repository use several forms of
documentation for different purposes.  README files orient users.  ADRs preserve
durable choices.  Doxygen comments explain implementation contracts near source.
Tests capture observable expectations.  AGENTS files help contributors and AI
tools navigate the project.

These forms become harmful when they compete as parallel sources of truth.  A
large `AGENTS.md` can become a second architecture manual that drifts away from
ADRs.  Tests can encode implementation accidents rather than intended behavior.
Comments can explain what code does while silently inventing rationale that was
never decided.  Generated reference documentation can be mistaken for maintained
source documentation.

The opposite problem also exists.  If ADRs are the only place where decisions
are recorded, a maintainer may need to open and reread many long documents merely
to discover which constraints apply to a change.  That friction creates pressure
to skip the architectural record, especially during small or AI-assisted edits.

A concise decision map solves a different problem than `AGENTS.md`.
`AGENTS.md` explains how to work in the repository: where files live, which
commands to use, what workflow boundaries matter, and where the governing
records can be found.  `doc/decisions.md` explains what architectural decisions
currently exist in compact form.  Neither document should become a substitute
for the ADRs themselves.

AI-assisted maintenance increases the importance of preserving decision lineage.
A model can often repair syntax or satisfy a failing test without knowing why a
constraint existed.  Repeated locally-correct edits can therefore cause gradual
architectural drift even when each individual change appears reasonable.

bashlog also has an unusually important documentation obligation because its
redaction behavior creates security expectations.  Public promises, explicit
non-promises, adversary/failure boundaries, and implementation constraints must
remain traceable to their architectural reasoning rather than being scattered
across source comments or marketing-style README claims.

## Decision Drivers

- Preserve reasoning, alternatives, and tradeoffs rather than only outcomes.
- Give contributors and AI-assisted tools a concise way to identify binding
  decisions without duplicating entire ADRs.
- Keep repository workflow guidance separate from architectural decision
  summaries.
- Keep implementation rationale close to code while preventing comments from
  inventing architectural history.
- Make conflicts between implementation and architectural intent visible.
- Support future reconstruction of why the system has its current shape.
- Make security promises and limitations traceable to the decisions that justify
  them.
- Allow verbose ADRs without making day-to-day architectural discovery
  unnecessarily burdensome.

## Decision

The project SHALL use a layered documentation hierarchy.

### README.md

`README.md` is the primary public orientation and public contract surface.  It
SHALL explain what bashlog is, how consumers obtain and source it, representative
usage, important guarantees, important limitations, and links to deeper
architecture and reference material.

Security-relevant public promises SHALL be stated directly rather than hidden
behind vague language such as "secure" or "safe."  Material non-promises and
threat-boundary limitations SHALL receive comparable visibility.

The README is not the canonical historical reasoning record.  Claims made there
SHOULD trace to ADRs or the normative specification.

### Architecture Decision Records

Architecture Decision Records under `doc/adr/` are the canonical record for
durable architectural and process decisions.  ADRs SHALL be intentionally
complete where the decision is consequential.

They should record, as applicable:

- intent and documentation posture;
- context;
- decision drivers;
- the selected decision;
- promises;
- non-promises;
- adversary and failure model;
- operational constraints;
- considered and rejected alternatives, including why they were rejected;
- consequences and accepted tradeoffs;
- source lineage;
- open questions and follow-ups;
- related, superseding, and superseded decisions.

Not every trivial decision requires every heading.  Consequential security,
trust, compatibility, data-loss, public-API, or failure-semantics decisions
SHOULD err toward explicitness rather than brevity.

Each ADR SHALL include an `Operational Constraints` section when the decision can
be translated into concrete implementation or review rules.  This section is a
compact derivative of the full reasoning.  It exists so a contributor or AI tool
can quickly determine what must remain true while still having the full ADR
available when the reason matters.

### doc/decisions.md

The project SHALL maintain `doc/decisions.md` as a concise architectural decision
map.

Each listed ADR SHALL receive a one-to-three-sentence summary that states the
operative decision or, for a proposed ADR, clearly identifies the proposal.  Each
summary SHALL link to the governing ADR.

`doc/decisions.md` SHALL NOT reproduce full rationale, rejected alternatives, or
long-form consequences.  Those belong in the ADR.

When one ADR supersedes part of another, the decision map SHOULD summarize the
current effective rule and link to the relevant records so readers do not need to
infer current policy from contradictory historical wording.

A change that alters an ADR's operative decision SHOULD update
`doc/decisions.md` in the same change.  Purely explanatory ADR edits that do not
change the decision need not mechanically rewrite the summary.

### AGENTS.md

`AGENTS.md` SHALL remain a concise operational map.  It MAY summarize salient
constraints, repository locations, validation commands, and workflow boundaries,
but it SHALL point to ADRs, `doc/decisions.md`, and normative documentation rather
than reproduce architectural rationale at length.

### Project Specification

`doc/bashlog-spec.md` SHALL define the accepted normative observable public
behavior of bashlog: function signatures, accepted values, matching semantics,
ordering, return statuses, output behavior, and other public contracts.

ADRs explain **why important choices were made**.  The specification defines
**what conforming implementation behavior must be**.

Specification acceptance and implementation conformance are distinct.  An
accepted specification may govern work before the runtime has been implemented;
the repository MUST NOT describe behavior as implemented merely because the
normative document has been accepted.

If an ADR is later superseded while public behavior changes, the specification
SHOULD describe the new normative behavior rather than preserving obsolete
history.

### Doxygen Source Documentation

Doxygen comments SHALL preserve implementation-level intent, interfaces,
invariants, assumptions, edge cases, examples, failure behavior, and local
security constraints close to the source.

The exact syntax and structure are normative and are governed by ADR-007 and
`doc/documentation-standard.md`.  bashlog intentionally uses the same
`bash-doxygen`-compatible documentation model used by related Bash projects;
maintainers MUST NOT replace it with merely similar prose comments.

Source comments MUST NOT invent historical rationale that is absent from the
architectural record.  Ambiguity should be surfaced explicitly.

### Tests and CI

Tests and CI SHALL verify observable behavior and selected architectural
invariants.  Passing tests do not supersede an ADR.  A conflict between a test,
implementation, specification, and governing ADR must be investigated rather
than silently resolved in favor of whichever artifact is easiest to change.

Security promises SHOULD become negative as well as positive tests when
practical.  For example, a redaction test should not merely verify that a
replacement appears; it should also verify that the protected original does not
appear in observable output.

### Development and Review Sequence

Consequential work SHOULD begin by identifying the ADRs and constraints that
govern the affected area.  `doc/decisions.md` is the compact discovery surface;
full ADRs remain the reasoning authority.

Review SHOULD compare the completed change against those same constraints so that
validation includes architectural alignment, not only syntax and behavior.

## Promises

1. **Durable reasoning has one canonical home.**  ADRs remain the source of truth
   for why consequential architectural decisions exist.

2. **Current decisions are discoverable without discarding reasoning.**
   `doc/decisions.md` provides concise summaries and direct links rather than
   replacing the ADR corpus.

3. **Public claims remain traceable.**  README guarantees and limitations should
   be grounded in accepted decisions and normative specification behavior.

4. **Implementation documentation stays close to code.**  Doxygen comments
   preserve local contracts without becoming a parallel architecture history.

5. **Generated documentation remains derivative.**  Reference HTML is generated
   from maintained source and architectural records rather than becoming an
   independent source of truth.

6. **Tests provide evidence, not authority over intent.**  A passing suite does
   not silently override an architectural constraint.

## Non-Promises

1. The hierarchy does not guarantee that documentation can never drift.  It
   defines where conflicts must be resolved and what sources carry which kinds of
   authority.

2. `doc/decisions.md` does not contain enough information to replace reading the
   governing ADR when reasoning, alternatives, or edge cases matter.

3. `AGENTS.md` is not a comprehensive project specification.

4. Doxygen comments are not permission to invent historical reasoning that was
   never decided.

5. Tests do not prove that every architectural invariant is covered.

6. More documentation is not automatically better when it merely repeats syntax
   or creates contradictory duplicate sources.  The "more is more" posture is
   about preserving useful reasoning and contracts.

## Adversary and Failure Model

This documentation architecture is intended to resist forms of maintenance drift
including:

- a future contributor finding implementation but not the reason behind it;
- an AI-assisted change satisfying tests while violating a prior architectural
  boundary;
- a concise operational file gradually becoming a second, divergent architecture
  manual;
- README security language growing broader than the implementation can defend;
- generated reference documentation being treated as maintained source;
- source comments being rewritten to match accidental code behavior while the
  code is actually what drifted;
- a superseding ADR leaving readers unable to determine the current effective
  rule;
- and verbose ADRs becoming so difficult to discover that maintainers stop
  consulting them.

The model assumes maintainers are willing to follow and review the documented
hierarchy.  It cannot prevent an authorized contributor from intentionally
rewriting all authoritative sources consistently to make a new decision.  That
is a repository governance and review concern rather than a documentation-format
problem.

## Operational Constraints

- ADRs MUST remain the canonical source for durable architectural reasoning.
- `doc/decisions.md` MUST provide concise decision summaries with links to the
  governing ADRs.
- `doc/decisions.md` summaries SHOULD be one to three sentences per ADR.
- Proposed ADRs MUST be distinguishable from accepted decisions in the decision
  map.
- Changes to operative ADR decisions SHOULD update `doc/decisions.md` in the same
  change.
- `AGENTS.md` MUST remain concise and MUST point to governing documentation rather
  than duplicate it wholesale.
- Consequential ADRs SHOULD document promises, non-promises, and an adversary or
  failure model when those sections clarify boundaries.
- Doxygen comments MUST describe implementation intent without fabricating
  architectural history.
- Doxygen source comments MUST follow ADR-007 and the exact
  `doc/documentation-standard.md` syntax.
- A conflict between implementation and an ADR MUST be surfaced explicitly.
- Passing tests MUST NOT be treated as proof of architectural alignment.
- Consequential changes SHOULD be reviewed against the ADR constraints that
  governed their implementation.
- `doc/bashlog-spec.md` MUST remain aligned with accepted public-behavior
  decisions and implementation-facing Doxygen/test contracts.
- Specification acceptance MUST NOT be represented as implementation conformance
  without supporting runtime evidence.

## Considered Alternatives

### Put All Guidance in AGENTS.md

A single operational document is convenient for tooling because there is only
one place to read.

It was rejected because the document would inevitably become large, would
duplicate ADRs, and would make architectural rationale easier to silently edit
without preserving decision history.

### Use Only ADRs

ADRs can contain every relevant rule.

This was rejected because day-to-day contributors still benefit from a compact
map of current decisions, repository shape, commands, and high-frequency
constraints.  Requiring every task to rediscover every relevant long-form ADR
increases cognitive load and makes important rules easier to miss.

### Make doc/decisions.md a Complete Restatement of Every ADR

A comprehensive decision document could provide one central architecture manual.

It was rejected because it would immediately create a second source that must be
kept synchronized with the ADR corpus.  The decision map is intentionally short:
one to three sentences and a link.

### Treat Tests as the Effective Specification

Executable tests are precise and valuable.

They were rejected as the sole source of truth because tests describe selected
observable behavior and can also encode mistakes, omissions, or implementation
details.  They rarely preserve why an architectural boundary exists.

### Put All Public Behavior in ADRs

ADRs could define every function signature and current edge case.

It was rejected because ADRs are historical reasoning records.  A normative
specification is better suited to describing current behavior that may evolve
through later superseding decisions.

## Consequences

The repository carries more documentation than a minimal Bash project.  That is
intentional.  Maintainers spend less time reverse-engineering decisions and have
a stronger basis for rejecting plausible changes that violate prior constraints.

Maintainers incur a small synchronization obligation: when an operative decision
changes, the decision map and, where relevant, README/specification must be
updated with it.

The model requires discipline.  A new ADR is unnecessary for trivial changes,
but consequential changes should not bypass the architectural record merely
because code can be changed quickly.

For bashlog specifically, this structure provides a way to be exceptionally
verbose in the redaction ADRs without forcing every consumer to read the entire
security design before discovering the public guarantees.

## Source Lineage

This decision consolidates patterns used across Bootstrap, adrctl, bashdeps, and
mktext.  It is also informed by Wesley Dean's writing on ADRs and AI-assisted
development, particularly:

- https://wesleydean.com/blog/adrs_and_generative_ai/
- https://wesleydean.com/blog/documentation_and_ai/

The addition of `doc/decisions.md` follows the concise decision-summary model used
in Bootstrap while preserving the fuller ADR as the authority for reasoning.

## Open Questions and Follow-Ups

- Keep `doc/bashlog-spec.md`, public README claims, Doxygen contracts, and
  behavior tests synchronized as implementation progresses.
- The project may eventually generate portions of the ADR index automatically,
  but automation must not turn the decision map into generated opaque state.

## Related Decisions

- ADR-000: Capability Scope, Epistemic Honesty, and Separation of Concerns
- ADR-007: Doxygen-Based Verbose Source Documentation Standard
- ADR-008: Documentation-Driven, Test-Second Development
- ADR-009: Observable Behavior Testing Across Shipped Artifacts
- ADR-010: Generated Reference Documentation Is Ephemeral
- ADR-018: Redaction as an Opt-In Security Boundary
- ADR-019: Readability, Auditability, and Rejection of Obscurity
