# ADR-029: Compose a Mermaid Relationship Graph into the Generated ADR Index

Date: 2026-08-30

## Status

Accepted

## Intent and Documentation Posture

This Architecture Decision Record extends ADR-028 by making the ADR relationship graph part of bashlog's committed generated ADR landing page.

ADR-028 established the generated-and-committed `doc/adr/README.md`, the pinned documentation-only adrctl dependency, the maintained introduction/conclusion fragments, the Make-owned output path, and atomic replacement.  At that time, Mermaid graph serialization was intentionally deferred until adrctl provided a stable serializer.

adrctl v0.0.12 now provides `generate graph --format mermaid` as a raw text report, including node links.  This ADR records bashlog's decision to consume that representation as a second navigation surface alongside the generated table of contents.

The graph is useful documentation and navigation.  Clickable nodes are part of the generated representation when the Markdown renderer permits them, but bashlog does not position clickability as a headline feature or depend on it for basic ADR discoverability.

## Context

The generated ADR index already removes one form of duplication by deriving the ADR title/link list from the ADR corpus.  A text index is excellent for scanning titles and remains the primary conventional navigation surface.

ADRs also contain relationships that are difficult to perceive from a flat list.  Sequence edges show how the decision corpus evolved, while explicit Status-section relationships can show supersession and other intentional relationships.  A graph therefore answers a different question than the table of contents: not merely "what decisions exist?", but "how are these decisions connected?"

adrctl issue #15 and PR #16 introduced a shared graph model with DOT and Mermaid serializers.  The Mermaid serializer emits raw source, not Markdown fences, and emits `click` directives for each managed ADR node.  Link URL construction reuses the graph command's existing prefix and extension options.

The serializer's default link extension is `.html`, which is useful for generated HTML documentation but is not correct for bashlog's committed GitHub Markdown landing page.  bashlog therefore requests `.md` links explicitly.

Ordinary relative Markdown links in repository files are rewritten by GitHub relative to the file containing them.  Mermaid diagrams are rendered differently: GitHub serves the rendered diagram from an isolated `viewscreen.githubusercontent.com/markdown` context.  A relative Mermaid `click` URL is therefore resolved against that renderer host rather than against `doc/adr/README.md`.  This was verified after the initial implementation when clicking a node produced a URL such as:

```text
https://viewscreen.githubusercontent.com/markdown/ADR-029-compose-mermaid-relationship-graph-into-generated-adr-index.md
```

rather than the repository file URL.

For this GitHub-facing generated surface, bashlog must therefore supply an absolute canonical GitHub link prefix through adrctl's existing `-p` option.  This is repository-specific presentation policy and does not change adrctl's graph semantics.

## Decision Drivers

- Preserve the text TOC as the conventional ADR index.
- Add a visual representation of ADR sequence and explicit relationships.
- Reuse adrctl's graph semantics rather than reconstructing relationships in Make.
- Keep repository-specific Markdown layout and publication URLs in Make rather than in adrctl.
- Keep graph source text reviewable in ordinary Git diffs.
- Preserve direct `.md` navigation from graph nodes when the renderer supports Mermaid `click` directives.
- Avoid relative Mermaid node URLs that GitHub resolves against its isolated renderer host.
- Preserve deterministic committed output regardless of the local or CI branch performing generation.
- Preserve the offline documentation-generation boundary after dependencies are prepared.
- Preserve atomic replacement of the committed ADR landing page.
- Avoid adding Mermaid CLI, Node.js, Graphviz, or another rendering dependency merely to display the graph on GitHub.
- Keep the graph additive rather than making it the only route to an ADR.

## Decision

bashlog SHALL pin an adrctl release that supports:

```text
adrctl generate graph --format mermaid
```

The initial required release is adrctl v0.0.12.

`make adr-index` SHALL compose the generated landing page in this order:

1. the existing adrctl-generated table of contents, using the maintained introduction fragment;
2. a repository-owned `## Decision Relationships` heading;
3. a fenced Mermaid block containing raw output from `adrctl generate graph --format mermaid` with the repository-selected link prefix and `.md` extension;
4. the maintained conclusion fragment.

Conceptually:

````text
adrctl generate toc -i README.intro.md

## Decision Relationships

```mermaid
<adrctl generate graph --format mermaid -p ABSOLUTE_PREFIX -e .md>
```

README.outro.md
````

The code fences, section heading, ordering, output destination, canonical publication URL, and atomic replacement remain Make/repository concerns.  adrctl owns ADR discovery, graph semantics, serialization, and graph-node URL construction from the supplied prefix/extension inputs.

### Link Semantics

The Makefile SHALL expose:

```text
ADR_GRAPH_LINK_PREFIX ?= https://github.com/wesley-dean/bashlog/blob/main/$(ADR_DIR)/
```

The value MAY be overridden through the Make command line or exported environment for a fork, alternate canonical repository, or other publication surface.

For the committed ADR landing page, Make SHALL invoke graph generation with the conceptual options:

```text
-p "$(ADR_GRAPH_LINK_PREFIX)" -e .md
```

The default therefore produces absolute node URLs such as:

```text
https://github.com/wesley-dean/bashlog/blob/main/doc/adr/ADR-029-compose-mermaid-relationship-graph-into-generated-adr-index.md
```

The canonical `main` prefix is intentionally static.  The committed generated README must be deterministic when regenerated on a workstation, feature branch, or CI runner; deriving the current Git branch or commit into the generated URLs would make the committed output context-dependent and would break the existing clean-tree reproducibility check.

The ordinary generated TOC continues to use relative Markdown links because those are interpreted by GitHub in the repository-document context and remain useful in clones.  Only Mermaid `click` URLs require the absolute canonical prefix for GitHub's current renderer architecture.

The generated Mermaid source MAY contain `click` directives.  Those directives are useful navigation metadata and SHALL be retained in the committed generated output.  bashlog does not guarantee that every Mermaid renderer will make those nodes interactive; renderer policy remains outside bashlog's control.

### Dependency and Runtime Boundary

adrctl remains a documentation/development dependency only.  The dependency is not sourced or embedded into bashlog consumer artifacts and does not alter bashlog runtime behavior.

No Mermaid renderer is added as a bashlog dependency.  `make adr-index` generates source text only.  GitHub or another downstream Markdown renderer decides whether and how to render it visually.

The absolute graph-link prefix is static build configuration.  Generating the README does not query GitHub, inspect remote repository metadata, or require network access.

### Failure and Atomicity

TOC generation, graph generation, Markdown framing, and maintained outro composition SHALL all complete against a temporary candidate file before the selected `ADR_INDEX_FILE` is replaced.

A failure from either adrctl report SHALL prevent publication of the candidate file.  The previous committed ADR index SHALL not be intentionally replaced by partial TOC or partial graph output.

## Promises

1. The generated ADR landing page contains both a text TOC and Mermaid relationship graph.
2. The graph is generated from adrctl's shared ADR graph semantics rather than a bashlog-local relationship parser.
3. The default GitHub-facing graph uses absolute canonical URLs targeting `.md` ADR files under `main`.
4. `ADR_GRAPH_LINK_PREFIX` can override that publication prefix without changing the Make recipe.
5. Mermaid source remains human-readable and reviewable in the committed Markdown file.
6. `make adr-index` and `make docs` remain offline after dependency preparation.
7. The generated README remains atomically replaced only after complete successful composition.
8. The text TOC remains available even when a renderer does not support Mermaid or clickable nodes.
9. No Mermaid rendering runtime is added to bashlog consumer artifacts or documentation dependencies.
10. Regeneration remains deterministic rather than embedding the current feature branch or commit into the committed graph URLs.

## Non-Promises

1. bashlog does not promise that every Markdown renderer supports Mermaid.
2. bashlog does not promise that every Mermaid renderer enables clickable `click` directives.
3. The graph does not replace the ADR documents, the text TOC, or `doc/decisions.md` as documentation surfaces.
4. The graph does not infer relationships that are absent from adrctl's graph model.
5. The graph does not prove architectural correctness or completeness.
6. bashlog does not own Mermaid rendering, layout algorithms, browser behavior, or downstream security policy.
7. This decision does not require other repositories to adopt Mermaid graph generation.
8. The default graph URLs do not automatically follow a fork or feature branch; callers that need another publication base must override `ADR_GRAPH_LINK_PREFIX`.
9. The absolute GitHub URLs are not intended to replace the relative TOC links for local clones.

## Adversary and Failure Model

This decision considers:

- a malformed or incomplete graph replacing a valid committed README;
- a graph-generation failure after TOC generation succeeds;
- a dependency regression changing serializer output unexpectedly;
- graph links resolving to generated HTML instead of committed Markdown;
- relative Mermaid links resolving against GitHub's `viewscreen.githubusercontent.com/markdown` renderer host instead of the repository;
- a dynamic branch-derived prefix making committed output non-deterministic across environments;
- a stale canonical repository/default-branch prefix after a repository move or branch rename;
- repository-specific page layout or publication policy leaking into adrctl's semantic responsibility;
- introducing a renderer dependency with unnecessary execution authority;
- a downstream renderer declining to honor Mermaid or node clicks;
- Mermaid source becoming an opaque generated blob that reviewers cannot inspect; and
- documentation tooling accidentally crossing into bashlog's runtime artifacts.

Atomic candidate generation addresses partial-publication failures.  Pinning adrctl establishes expected dependency bytes but does not prove behavioral safety.  The adrctl dependency therefore remains part of the documentation trusted computing base described by ADR-028 and the project threat model.

A static, reviewable `ADR_GRAPH_LINK_PREFIX` avoids both GitHub's relative-URL renderer boundary and branch-dependent generated output.  Repository moves and default-branch renames remain explicit configuration changes rather than silently inferred behavior.

## Operational Constraints

- bashlog MUST pin adrctl v0.0.12 or a later intentionally reviewed release that preserves the required graph contract.
- `adr-index` MUST invoke `generate graph --format mermaid` through the prepared adrctl artifact.
- the committed GitHub-oriented graph MUST request `-e .md`.
- the committed GitHub-oriented graph MUST supply an absolute canonical prefix through `-p`.
- `ADR_GRAPH_LINK_PREFIX` MUST default to `https://github.com/wesley-dean/bashlog/blob/main/$(ADR_DIR)/` and MAY be overridden through Make/environment configuration.
- the Makefile MUST NOT derive the committed graph prefix from the current feature branch or commit.
- the graph section heading and Mermaid fences MUST remain repository-owned Markdown composition.
- raw Mermaid output MUST be written inside the fenced block without post-processing its graph semantics.
- `ADR_INDEX_FILE` MUST retain the configuration rules established in ADR-028.
- complete composition MUST occur before atomic replacement of the selected output file.
- `make docs` MUST remain offline after dependencies are prepared.
- adrctl and Mermaid rendering tooling MUST NOT become bashlog runtime dependencies.
- the ordinary text TOC MUST remain present as a non-Mermaid navigation path and MAY continue using relative repository links.

## Considered Alternatives

### Keep Only the Text TOC

This is adequate for finding ADRs by title and has the smallest output.  It was not selected because the relationship graph conveys sequence and explicit decision relationships that a flat list cannot communicate efficiently.

### Generate an Image and Commit It

A rendered SVG or PNG could provide a fixed visual representation.  It was rejected because it would require a renderer, create an additional generated artifact, reduce diff readability, and make the graph harder to inspect as source.

### Add Mermaid CLI or Node.js to `make docs`

This would permit local rendering validation.  It was rejected because bashlog only needs to produce Mermaid source for GitHub and compatible renderers.  Adding a substantial renderer toolchain would expand the documentation attack surface without improving the source-of-truth relationship model.

### Use DOT/Graphviz Instead

Graphviz remains a useful adrctl serialization and is already familiar in technical documentation.  Mermaid was selected for the committed GitHub landing page because GitHub renders fenced Mermaid directly from reviewable Markdown source without requiring a separately committed image.

### Let adrctl Emit Markdown Headings and Fences

This could reduce the Make recipe.  It was rejected because the graph is one report fragment inside a repository-specific page.  adrctl should own graph semantics and serialization; bashlog should own document layout and publication URL policy.

### Use the Graph's Default `.html` Links

This was rejected because the graph lives beside committed source ADR Markdown files, not a generated HTML ADR corpus.  Explicit `.md` links are the correct navigation target for this surface.

### Use Relative Mermaid `click` URLs

This was the initial implementation assumption.  It was rejected after direct GitHub use showed that Mermaid is rendered from an isolated `viewscreen.githubusercontent.com/markdown` context and relative `click` URLs resolve against that host rather than against the repository README.  Ordinary Markdown relative-link behavior therefore cannot be assumed for Mermaid interaction directives.

### Derive the Current Branch or Commit into Graph URLs

This could make feature-branch previews link to the same feature branch.  It was rejected for the committed generated file because the README must regenerate to the same bytes in local and CI contexts.  A branch- or commit-derived prefix would make generated output depend on where generation happened and would conflict with the clean-tree reproducibility check.

### Remove the Text TOC After Adding the Graph

This was rejected because the graph is complementary rather than superior for every navigation task, and Mermaid rendering/clickability is downstream-renderer-dependent.

## Consequences

The committed ADR README is larger because it carries readable Mermaid graph source in addition to the TOC.  That is an intentional tradeoff: the graph is useful repository-facing documentation and remains deterministic generated text.

The graph's `click` lines now contain longer absolute GitHub URLs instead of compact relative basenames.  The added verbosity is accepted because it is generated, reviewable, and necessary for reliable navigation through GitHub's isolated Mermaid rendering context.

The canonical repository/default-branch URL becomes explicit Make configuration.  A repository move or default-branch rename therefore requires updating `ADR_GRAPH_LINK_PREFIX`; this is preferable to runtime discovery because it preserves deterministic offline generation.

Updating the adrctl pin expands the exact documentation dependency bytes trusted by the repository, but it does not add a new dependency category or runtime boundary.

Future ADR additions may change both the TOC and graph in the same generated diff.  CI's existing `make docs` cleanliness check will detect a stale committed README when the generated representation changes.

The graph also creates a concrete dogfooding path for adrctl's Mermaid serializer.  If serializer usability or link behavior is awkward in real repositories, bashlog can provide evidence for future adrctl improvements without embedding workarounds into bashlog's graph semantics.

## Source Lineage

This decision implements the future graph-composition path anticipated by ADR-028 after adrctl issue #15 was completed in PR #16 and released as v0.0.12.

The relative-link correction was added after direct use of the merged GitHub-rendered graph demonstrated that Mermaid interaction URLs are resolved from GitHub's isolated `viewscreen.githubusercontent.com/markdown` rendering context rather than from the containing repository Markdown document.

The responsibility split remains the one established in ADR-028:

```text
adrctl
    -> ADR-specific report content and URL construction from supplied inputs

Make
    -> repository-specific composition, publication prefix, and placement
```

The serializer remains generic; bashlog supplies the absolute GitHub prefix appropriate to its committed landing page.

## Related Decisions

- ADR-003: Make as the Canonical Orchestration Interface
- ADR-005: Dependency Management and Explicit Network Boundaries
- ADR-010: Generated Reference Documentation Is Ephemeral
- ADR-019: Readability, Auditability, and Rejection of Obscurity
- ADR-028: Generate Committed ADR Navigation with a Pinned adrctl Documentation Dependency
