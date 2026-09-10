# ADR-031: Make the Generated ADR Landing Page Ephemeral

Date: 2026-09-09

## Status

Accepted

## Intent and Documentation Posture

This Architecture Decision Record changes the storage policy for bashlog's
generated ADR landing page while preserving the useful documentation behavior
established by ADR-028 and simplified by ADR-030.

bashlog SHALL continue to maintain repository-specific introduction and conclusion
fragments, SHALL continue to use `adrctl generate toc` for mechanical ADR
enumeration, and SHALL continue to use the resulting composite Markdown document
as the Doxygen main page.  The composite `doc/adr/README.md` SHALL now be an
ignored, ephemeral documentation-build input rather than a committed repository
artifact.

The maintained ADRs, `README.intro.md`, `README.outro.md`, and
`doc/decisions.md` remain source.  The generated ADR landing page and generated
Doxygen HTML are derivative outputs.

This decision does not restore the ADR relationship graph removed by ADR-030.
Routine publication remains based on the linked textual ADR index.

## Context

ADR-010 established a broad principle that generated reference documentation is
derivative and should not be committed merely to support publication.  ADR-028
later made a deliberate exception for `doc/adr/README.md`: the generated file was
small, reviewable, and useful as GitHub's automatic landing page when a reader
entered `doc/adr/` directly.

That exception also created a synchronization obligation.  Every ADR addition,
rename, or title change that affected generated navigation required a second
mechanical file change.  CI and reviewers therefore had to distinguish meaningful
maintained documentation changes from a derived representation that existed
primarily so another documentation generator could consume it.

ADR-029 increased that cost by adding generated relationship-graph content.
ADR-030 removed the graph after practical publication showed that its navigation
value did not justify the renderer and composition complexity.  The remaining
generated README is much smaller, but the underlying source-versus-derived
ownership question remains.

The bashdeps repository subsequently adopted the cleaner model directly: it keeps
`README.intro.md` and `README.outro.md` as maintained source, generates an ignored
`doc/adr/README.md` during documentation work, and uses that ephemeral file as the
Doxygen main page.  That model preserves the published reader experience without
requiring source control to retain a mechanically reproducible intermediate file.

bashlog's primary requirement for the composite page is the published Doxygen
site.  Direct GitHub directory rendering is useful, but it does not justify a
second maintained synchronization surface when readers can navigate the ADR corpus
through `doc/decisions.md`, repository links, individual ADR files, and the
published reference site.

The project should therefore align the ADR landing page with the same source and
derivative boundary already applied to Doxygen output: maintained material belongs
in Git; reproducible publication intermediates do not need to be committed merely
because they are readable text.

## Decision Drivers

- Keep the published documentation site useful as a project and ADR landing page.
- Preserve maintained repository-specific explanatory prose around the ADR index.
- Continue deriving ADR titles and links mechanically from authoritative ADR files.
- Eliminate synchronization work for a derivative Markdown build input.
- Keep the source/generated boundary easy to explain and inspect.
- Preserve the existing offline `make docs` contract after dependencies are
  prepared.
- Preserve adrctl as pinned documentation-only tooling outside bashlog runtime and
  distribution artifacts.
- Preserve atomic ADR-index generation.
- Keep routine ADR navigation textual and renderer-independent.
- Avoid duplicating intro/outro fragments as standalone Doxygen pages when their
  content is already composed into the generated main page.
- Keep contributor guidance accurate on a pristine checkout where the generated
  README does not yet exist.

## Decision

### Maintained source and generated state

The repository SHALL continue to maintain:

```text
doc/adr/README.intro.md
doc/adr/README.outro.md
```

alongside the authoritative ADR corpus.

The documentation build SHALL generate:

```text
doc/adr/README.md
```

from the maintained framing and adrctl-generated linked ADR table of contents.

`doc/adr/README.md` SHALL be ignored by Git and SHALL NOT be committed as
maintained repository state.

The responsibility boundary is:

```text
doc/adr/*.md
README.intro.md
README.outro.md
doc/decisions.md
    = maintained documentation source

adrctl generate toc
    = mechanical ADR title/link enumeration

Make
    = composition, placement, sequencing, and atomic replacement

doc/adr/README.md
    = ephemeral documentation-build input

doc/reference/
    = ephemeral Doxygen output
```

### Preserve `make adr-index`

`make adr-index` SHALL remain the focused generator for the composite ADR landing
page.

It SHALL continue to:

1. consume already-prepared `vendor/adrctl.bash` state;
2. require the maintained introduction and conclusion fragments;
3. invoke adrctl through Bash;
4. generate the linked textual ADR table of contents;
5. compose the complete page at a same-destination temporary path; and
6. replace `ADR_INDEX_FILE` only after complete successful generation.

The target SHALL NOT synchronize dependencies or intentionally access the network.
`ADR_INDEX_FILE` MAY remain configurable as established by ADR-028, with
`$(ADR_DIR)/README.md` remaining the conventional default.

The existing generation recipe MAY continue to append the maintained outro after
TOC generation rather than using adrctl's `-o` option.  This decision concerns
ownership and publication state, not a requirement to rewrite already-correct
composition mechanics.

### Preserve the offline documentation boundary

`make docs` SHALL continue to consume prepared documentation dependencies and
SHALL NOT invoke `make deps`, synchronize repository dependencies, or otherwise
intentionally access the network.

`make docs` SHALL continue to ensure ADR-index generation occurs before Doxygen is
invoked.  Doxygen SHALL continue to use the generated `doc/adr/README.md` as its
main page.

This preserves the established operational sequence:

```text
make deps          # explicit network-capable preparation boundary
make docs          # offline generation from prepared state
```

### Cleanup semantics

`make docs-clean` SHALL remain focused on generated Doxygen reference output under
`doc/reference/`.  It SHALL NOT be made responsible for deleting the ADR landing
page as a prerequisite of `make docs`, because keeping those operations independent
avoids unnecessary ordering hazards under parallel Make execution.

`make distclean` SHALL remove the generated ADR landing page along with other
repository-generated state.

A successful `make docs` MAY therefore leave ignored `doc/adr/README.md` available
for local inspection after Doxygen generation completes.

### Doxygen presentation

The Doxyfile SHALL continue to use:

```text
USE_MDFILE_AS_MAINPAGE = doc/adr/README.md
```

The maintained `README.intro.md` and `README.outro.md` fragments SHOULD be excluded
from standalone Doxygen page discovery because their content is already composed
into the main page.  They remain source inputs to the Make/adrctl composition
process rather than independently published pages.

Normal documentation generation SHALL NOT add an ADR relationship graph, Mermaid
relationship block, DOT/Graphviz relationship rendering, or graph-specific link
configuration.  ADR-030 continues to govern that boundary.

### Repository navigation

Contributor and public documentation SHALL NOT require
`doc/adr/README.md` to exist in a pristine checkout.

Repository-facing navigation SHOULD point readers to `doc/decisions.md` and the
ADRs under `doc/adr/`.  Documentation may explain that the published Doxygen site
contains the generated complete ADR index and that `make adr-index` can create the
same intermediate page locally after dependencies are prepared.

The loss of GitHub's automatic `doc/adr/README.md` directory landing page is an
accepted consequence of keeping generated navigation out of maintained source
control.

## Promises

1. The published Doxygen site continues to use a project-specific ADR landing page
   as its main page.
2. The landing page continues to contain a linked textual ADR index generated by
   adrctl from authoritative ADR source.
3. Repository-specific framing remains maintained in `README.intro.md` and
   `README.outro.md`.
4. `doc/adr/README.md` is reproducible but is no longer committed.
5. `make adr-index` remains atomic with respect to its selected destination.
6. `make docs` remains offline after repository dependencies have been prepared.
7. adrctl remains documentation/development tooling and remains outside all
   bashlog consumer artifacts and runtime behavior.
8. Normal publication continues to omit the ADR relationship graph.
9. A complete cleanup removes the generated ADR landing page.
10. Contributor documentation does not depend on the ephemeral README being
    present in a pristine checkout.

## Non-Promises

1. Entering `doc/adr/` on GitHub is no longer promised to show a generated README
   containing the complete ADR index.
2. The generated landing page is not an architectural source of truth.
3. The generated landing page does not replace `doc/decisions.md`.
4. `make docs-clean` does not promise to remove every generated documentation
   intermediate; `make distclean` owns complete generated-state cleanup.
5. This decision does not change bashlog runtime behavior or public API.
6. This decision does not change the adrctl version pin merely to adopt the new
   ownership model.
7. This decision does not restore, require, or prohibit explicit ad hoc use of
   adrctl's graph command outside routine publication.
8. This decision does not require unrelated maintained diagrams to be removed.

## Adversary and Failure Model

The adrctl executable remains part of the documentation trusted computing base.
Its pinned SHA-256 digest authorizes expected bytes but does not establish that
those bytes are behaviorally safe.  The existing dependency-review obligation
therefore remains unchanged.

A failed ADR generator could otherwise leave a truncated Markdown file.  The
existing same-directory temporary candidate and replacement-on-success pattern
continues to bound that ordinary failure mode.

Because the generated README is ignored, stale local generated state can remain
after ADR changes.  This is acceptable because `make docs` regenerates the page
before Doxygen consumes it.  Published output therefore derives from the current
checkout rather than trusting a previously generated local page.

A documentation consumer that runs Doxygen directly instead of the canonical
`make docs` target may encounter a missing or stale main-page file.  This project
continues to define Make as the canonical orchestration interface; direct Doxygen
invocation does not receive the same orchestration guarantees.

Removing the generated file from source control also means ordinary code review no
longer shows the derived ADR list as a separate diff.  Reviewers instead inspect
the authoritative ADR changes, while CI/documentation generation exercises the
serialization path itself.

The implementation MUST continue to prevent documentation-only dependencies from
entering the maintained source closure or generated consumer artifacts.

## Operational Constraints

- `doc/adr/README.intro.md` and `doc/adr/README.outro.md` MUST remain maintained
  source.
- `doc/adr/README.md` MUST be ignored and MUST NOT be committed as generated
  navigation.
- `make adr-index` MUST consume prepared adrctl state and MUST remain offline.
- ADR-index generation MUST continue to replace its selected output only after
  successful complete composition.
- `make docs` MUST generate the ADR index before invoking Doxygen and MUST remain
  offline after dependency preparation.
- Doxygen MUST continue to use the generated ADR landing page as its main page.
- `make docs-clean` MUST continue to remove `doc/reference/` without introducing a
  race with ADR-index generation.
- `make distclean` MUST remove the generated ADR landing page.
- adrctl MUST remain outside bashlog runtime and distributed artifacts.
- normal documentation generation MUST NOT invoke `adrctl generate graph` or add a
  relationship-graph section.
- repository contributor guidance MUST NOT assume the ephemeral README exists in a
  pristine checkout.

## Considered Alternatives

### Continue committing the generated README

This preserves GitHub's automatic directory landing page and makes generated ADR
navigation visible in ordinary diffs.  It was rejected because the file is fully
reproducible, primarily serves the generated documentation site, and creates a
synchronization obligation without adding authoritative information.

### Move the generated page outside `doc/adr/`

A dedicated build directory would make generated ownership visually obvious.
This was not selected because the existing Doxygen configuration, adrctl-relative
links, configurable output convention, and local inspectability already work well
at `doc/adr/README.md`.  Git ignore status is sufficient to establish ownership
without relocating a working interface.

### Make `docs-clean` remove the generated README

This would make `docs-clean` mean all documentation intermediates.  It was rejected
for the normal clean target because `docs` already coordinates ADR generation and
Doxygen cleanup, and making both generated targets manipulate the same path family
creates unnecessary parallel-build ordering concerns.  Complete cleanup belongs
in `distclean`.

### Generate the page only in the GitHub Pages workflow

This would keep local repositories cleaner, but local `make docs` would no longer
produce the same documentation shape as CI.  The canonical Make target should
remain the shared local and CI orchestration surface.

### Retain a small committed `doc/adr/README.md` as a pointer

A static pointer could preserve GitHub directory behavior, but it would make the
README a maintained file while Doxygen needs a generated file at the same path.
Using one path for two ownership models would be confusing and would cause normal
builds to overwrite maintained source.

### Restore or replace the relationship graph

The storage-policy change does not alter ADR-030's value assessment.  The linked
textual index remains sufficient for routine navigation, so relationship-graph
publication remains outside this decision.

## Consequences

The published site retains the useful ADR-oriented main page, while the repository
no longer records a mechanically generated intermediate file in every relevant ADR
change.

A pristine checkout contains the maintained framing and ADR source but not the
composite `doc/adr/README.md`.  Running `make adr-index` after dependency
preparation creates it, and `make docs` regenerates it before publication.

Direct GitHub browsing of the ADR directory loses the automatic generated landing
page.  Readers retain `doc/decisions.md`, direct ADR files, repository-level links,
and the published reference site as navigation surfaces.

The model becomes easier to explain consistently across the related repositories:
humans maintain framing and architectural source; adrctl derives navigation; Make
owns composition; Doxygen consumes the ephemeral page; Pages publishes generated
HTML.

Runtime behavior, release artifacts, dependency pinning, the offline documentation
boundary, and the graph-removal decision remain unchanged.

## Superseded Decisions

This ADR supersedes the portions of ADR-028 that require the generated
`doc/adr/README.md` to be committed and that make GitHub's ADR-directory landing
page a promised documentation surface.  ADR-028's pinned adrctl dependency,
maintained framing, configurable output path, atomic generation, Make ownership,
offline-after-preparation behavior, and runtime separation remain in force.

This ADR also supersedes the portions of ADR-030 that describe the textual ADR
landing page as committed or assume that GitHub and Doxygen consume the same
committed generated document.  ADR-030's removal of routine relationship-graph
generation and preservation of explicit adrctl graph capability remain fully in
force.

ADR-010's general ephemeral generated-documentation posture is reinforced rather
than superseded.

## Related Decisions

- ADR-003: Make as the Canonical Orchestration Interface
- ADR-005: Dependency Management and Explicit Network Boundaries
- ADR-010: Generated Reference Documentation Is Ephemeral
- ADR-019: Readability, Auditability, and Rejection of Obscurity
- Partially supersedes: ADR-028: Generate Committed ADR Navigation with a Pinned adrctl Documentation Dependency
- Related to: ADR-030: Remove the Relationship Graph from Generated ADR Navigation
