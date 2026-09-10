# ADR-030: Remove the Relationship Graph from Generated ADR Navigation

Date: 2026-09-09

## Status

Accepted

## Intent and Documentation Posture

This Architecture Decision Record supersedes ADR-029's decision to include a
Mermaid relationship graph in bashlog's generated ADR landing page.

The generated and committed textual ADR index established by ADR-028 remains in
force.  The pinned `adrctl` documentation dependency, maintained introduction and
conclusion fragments, configurable index destination, atomic replacement, and
offline-after-preparation documentation boundary also remain in force.

This decision removes only the automatic relationship-graph composition from
`make adr-index` and, transitively, `make docs`.  It does not remove graph
generation from `adrctl`, prohibit maintainers from generating a graph explicitly
when useful, or remove unrelated diagrams from bashlog documentation.

## Context

ADR-029 added an ADR relationship graph to `doc/adr/README.md` after adrctl gained
a Mermaid serializer.  The graph was intended to complement the textual table of
contents by exposing sequence and explicit relationships among decisions while
remaining reviewable as generated Markdown source.

Practical publication exposed a renderer mismatch.  bashlog's GitHub Pages
workflow uses the Doxygen package supplied by Ubuntu 24.04, currently Doxygen
1.9.8.  That version does not natively render fenced Mermaid blocks, so the
Mermaid source in the generated ADR landing page is presented as literal code in
the Doxygen output.  Native Mermaid support was added to Doxygen much later, in
Doxygen 1.17.0.

There are technically viable ways to retain a visual graph.  The project could
install a newer Doxygen, add a Mermaid rendering toolchain, generate a separate
DOT/Graphviz image, maintain different GitHub-facing and Doxygen-facing ADR
landing pages, or conditionally transform the document during publication.  Each
approach introduces additional renderer, dependency, configuration, generated
artifact, or dual-surface complexity.

Experience with the generated graph also changed the value assessment behind
ADR-029.  The linked textual ADR index remains the primary navigation surface,
while the graph adds comparatively little practical navigation value.  The
additional composition logic, absolute Mermaid link configuration, generated
source volume, renderer-specific behavior, and publication concerns are no longer
justified by that incremental value.

This decision therefore treats the observed value-to-complexity ratio as the
primary reason to simplify the documentation path.  Doxygen 1.9.8's Mermaid
behavior is useful evidence that exposed the integration cost; this ADR does not
claim that upgrading Doxygen would make the graph architecturally necessary or
valuable enough to retain.

## Decision Drivers

- Keep the committed ADR landing page useful and easy to review.
- Preserve the linked textual ADR index as the normal navigation surface.
- Avoid renderer-specific documentation composition when it provides little
  practical value.
- Keep `make docs` compatible with the repository's current Doxygen publication
  environment without adding a Mermaid runtime or a parallel rendering path.
- Reduce generated Markdown volume and repository-specific graph-link
  configuration.
- Preserve ADR-028's atomic generation and offline-after-preparation boundaries.
- Preserve adrctl as the single source of ADR title/link enumeration for the
  generated textual index.
- Keep adrctl's graph capability available for explicit use without making it a
  bashlog publication requirement.
- Avoid broadening this cleanup into unrelated threat-model, architecture, or
  other maintained diagrams.

## Decision

The normal generated ADR landing page SHALL contain the adrctl-generated textual
ADR index plus the maintained repository introduction and conclusion fragments.
It SHALL NOT automatically include an ADR relationship graph.

`make adr-index` SHALL continue to:

1. require already-prepared `vendor/adrctl.bash` state;
2. invoke adrctl through Bash;
3. generate the ADR table of contents from the project's ADR corpus using the
   maintained introduction fragment;
4. append the maintained conclusion fragment;
5. build the complete candidate at a same-destination temporary path; and
6. replace the configured `ADR_INDEX_FILE` only after successful composition.

Conceptually, the generated-content portion returns to:

```bash
bash "$(ADRCTL)" generate toc -i "$(ADR_INDEX_INTRO)" >"$$tmp"
cat "$(ADR_INDEX_OUTRO)" >>"$$tmp"
```

The actual Make recipe SHALL retain its existing error handling, temporary-file
cleanup, configured paths, and atomic replacement behavior.

The graph-specific `ADR_GRAPH_LINK_PREFIX` Make variable SHALL be removed because
normal ADR-index generation no longer emits graph-node URLs.  `make adr-index`
SHALL no longer add a `Decision Relationships` heading, Mermaid fences, or invoke
`adrctl generate graph`.

`make docs` SHALL continue to invoke `adr-index` before Doxygen generation as
required by ADR-028.  Doxygen SHALL therefore receive the same committed ADR
landing page that GitHub readers see, without a generated relationship-graph
block.

The pinned adrctl dependency SHALL remain because the textual index still uses
`adrctl generate toc`.  This decision does not alter adrctl's graph serializer or
its public `generate graph` command.  A maintainer MAY invoke that command
explicitly for investigation or an ad hoc report, but its output is no longer a
required bashlog documentation artifact.

This decision applies specifically to the generated ADR relationship graph.  It
SHALL NOT be interpreted as requiring removal of independently maintained
Mermaid, DOT, Graphviz, threat-model, architecture, or other diagrams whose value
and governance arise from separate concerns.

## Promises

1. The generated `doc/adr/README.md` retains a linked textual ADR index.
2. The textual index continues to derive ADR titles and links from adrctl rather
   than from a second bashlog-local parser.
3. The generated ADR landing page no longer includes an automatically generated
   relationship graph.
4. `make adr-index` continues to replace the selected output atomically only
   after complete successful composition.
5. `make docs` remains offline after repository dependencies have been prepared.
6. adrctl remains a documentation/development dependency and remains outside
   bashlog runtime and distribution artifacts.
7. Unrelated maintained diagrams are unaffected by this decision.

## Non-Promises

1. bashlog does not promise that an ADR relationship graph will be published in
   another format or location.
2. bashlog does not remove or deprecate adrctl's `generate graph` capability.
3. bashlog does not prohibit maintainers from generating ad hoc relationship
   graphs outside the normal documentation pipeline.
4. This decision does not change Doxygen versions, GitHub Pages infrastructure,
   Graphviz availability, or other documentation tooling except where graph
   composition is removed from the ADR-index path.
5. This decision does not remove Mermaid or other diagrams governed by separate
   documentation or security decisions.
6. The textual index does not attempt to encode every relationship among ADRs;
   the ADR documents and `doc/decisions.md` remain the authoritative sources for
   decision lineage and summaries.

## Adversary and Failure Model

The primary concern in this decision is documentation complexity rather than a
new runtime security boundary.  The existing documentation trusted computing base
still includes adrctl because the generated textual index executes it.

The simplified path reduces several failure surfaces that ADR-029 introduced:

- Mermaid source being shown literally by a renderer that does not support it;
- graph-specific absolute URLs becoming stale after repository or branch changes;
- renderer-specific graph behavior producing inconsistent navigation surfaces;
- graph generation failing after textual TOC generation succeeds; and
- large generated graph diffs obscuring the smaller navigation changes reviewers
  actually need to inspect.

The remaining ADR-index failure model is the one established by ADR-028.  A
failed adrctl TOC generation or failed conclusion composition must not
intentionally replace the prior committed index with partial output.

Removing the relationship graph does not reduce the need to review the adrctl
pin as executable documentation tooling.  Checksum pinning establishes expected
bytes, not behavioral trustworthiness.

## Operational Constraints

- `make adr-index` MUST continue to consume prepared `vendor/adrctl.bash` state.
- `make adr-index` MUST continue to use adrctl for ADR title/link enumeration.
- `make adr-index` MUST NOT invoke `adrctl generate graph` as part of normal
  generated ADR navigation.
- the generated ADR landing page MUST NOT add a relationship-graph section as a
  normal documentation-generation step.
- graph-specific Make configuration used only for published graph-node links MUST
  be removed.
- the maintained ADR introduction and conclusion fragments MUST remain source.
- the selected ADR index file MUST continue to be generated atomically.
- `make docs` MUST continue to invoke ADR-index generation and MUST remain offline
  after dependencies are prepared.
- adrctl MUST remain outside bashlog runtime and distributed artifacts.
- unrelated maintained diagrams MUST NOT be removed merely because this ADR
  removes the generated ADR relationship graph.

## Considered Alternatives

### Keep the Existing Mermaid Graph

The current implementation is compact in Make and renders correctly on GitHub.
It was rejected because the graph adds limited practical value while producing a
large generated block and a renderer mismatch in the current Doxygen publication
path.

### Upgrade Doxygen to a Version with Native Mermaid Support

A newer Doxygen can understand Mermaid directly.  This was not selected because
it would make the repository own a newer Doxygen acquisition/versioning decision
primarily to retain a low-value navigation enhancement.  It would also move the
project away from the straightforward Ubuntu 24.04 documentation environment.

### Add Mermaid CLI or Another Mermaid Renderer

A dedicated renderer could convert Mermaid source before or during Doxygen
publication.  This was rejected because it would expand the documentation trusted
computing base and toolchain for functionality that has not proven valuable
enough to justify that cost.

### Generate DOT and Render with Graphviz

adrctl can serialize the relationship model as DOT, and Graphviz is a mature
renderer.  A generated SVG or PNG could therefore be included in Doxygen output.
This was rejected because it introduces an additional generated artifact and a
renderer-specific publication path while preserving the underlying low-value
relationship visualization.

### Maintain Separate GitHub and Doxygen ADR Landing Pages

The repository could keep Mermaid for GitHub and produce a graph-free or differently
rendered page for Doxygen.  This was rejected because two presentation variants
would complicate generation, review, and reproducibility solely to retain the
graph.

### Keep the Graph Outside `make docs` but Continue Generating It in `adr-index`

This would require `make docs` to use a second ADR landing-page path or otherwise
exclude part of the committed index from Doxygen.  It was rejected because the
simpler policy is for the normal generated ADR landing page itself to omit the
graph.

### Remove adrctl Entirely

The relationship graph is only one use of adrctl.  ADR-028 still uses adrctl to
generate the linked textual index and thereby avoids duplicating ADR enumeration
logic in Make.  Removing adrctl would therefore discard a useful, governed
capability outside the scope of this decision.

## Consequences

The generated ADR README becomes materially smaller and easier to inspect.  The
same document can be consumed by GitHub and the repository's current Doxygen
publication path without exposing a Mermaid relationship block as literal code.

Readers lose the always-present visual relationship graph.  They retain the
linked textual ADR index, `doc/decisions.md`, explicit relationships recorded in
individual ADRs, and the ability to generate an adrctl graph explicitly when a
visualization is useful.

The Makefile loses graph-specific composition commands and the canonical
GitHub-link-prefix variable.  Atomic generation, configurable index placement,
maintained framing, and the offline documentation boundary remain unchanged.

The decision reduces publication complexity without changing bashlog runtime
behavior, consumer artifacts, the adrctl dependency pin, or adrctl's graph
capability.

## Superseded Decisions

This ADR supersedes ADR-029 in full.  The requirement that the committed ADR
landing page contain a Mermaid relationship graph, the graph-specific link-prefix
configuration, graph composition, Mermaid framing, and associated publication
promises are no longer operative.

ADR-028 remains in force.  Its generated textual ADR index, pinned adrctl
documentation dependency, maintained framing fragments, configurable output,
atomic replacement, committed README, and offline-after-preparation behavior
continue to govern the documentation path.  ADR-028's optional future graph
composition was realized by ADR-029 and is no longer part of normal publication
policy under this decision.

## Related Decisions

- ADR-003: Make as the Canonical Orchestration Interface
- ADR-005: Dependency Management and Explicit Network Boundaries
- ADR-010: Generated Reference Documentation Is Ephemeral
- ADR-019: Readability, Auditability, and Rejection of Obscurity
- ADR-028: Generate Committed ADR Navigation with a Pinned adrctl Documentation Dependency
- Supersedes: ADR-029: Compose a Mermaid Relationship Graph into the Generated ADR Index
