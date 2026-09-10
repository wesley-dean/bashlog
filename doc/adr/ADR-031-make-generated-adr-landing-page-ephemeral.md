# ADR-031: Make the Generated ADR Landing Page Ephemeral

Date: 2026-09-09

## Status

Accepted

## Intent and Documentation Posture

This decision changes the retention policy for bashlog's generated ADR landing
page.  The maintained `README.intro.md` and `README.outro.md` framing, pinned
adrctl dependency, linked textual ADR table of contents, atomic generation, and
offline-after-preparation documentation boundary remain in force.

The generated `doc/adr/README.md` is now an ephemeral documentation-build input
rather than committed repository state.  Doxygen continues to use that generated
file as the published site's main page.

This decision does not restore the ADR relationship graph removed by ADR-030.
Normal publication remains text-oriented and renderer-independent.

## Context

ADR-028 established generated ADR navigation and deliberately committed
`doc/adr/README.md` because GitHub renders a README when a reader browses the ADR
directory.  ADR-030 later removed graph composition while expressly preserving
ADR-028's committed-README policy.

Experience with the documentation workflow has clarified the more important
consumer.  The generated README primarily exists to give the published Doxygen
site a useful project-level body and a complete linked ADR index.  The same
content can be generated deterministically whenever documentation is built from
the maintained ADR corpus and framing fragments.

Committing the generated file creates a second synchronization obligation without
adding a second source of knowledge.  An ADR change can make the committed README
stale even though all authoritative source remains correct.  CI can detect that
drift, but detection exists only because a derivative intermediate artifact was
promoted into maintained repository state.

The related bashdeps project now uses the cleaner boundary: maintained framing and
ADRs are committed; the composed ADR landing page and Doxygen HTML are generated.
Applying that same boundary to bashlog reduces generated-state bookkeeping while
preserving the published reader experience.

## Decision Drivers

- Preserve a useful project-level landing page on the published Doxygen site.
- Keep stable explanatory prose and ADR reasoning in maintained source.
- Keep ADR enumeration mechanically synchronized through adrctl.
- Avoid committing derivative navigation solely to feed another generated
  artifact.
- Preserve the existing offline documentation boundary.
- Preserve atomic generation and explicit dependency trust boundaries.
- Keep normal ADR navigation graph-free under ADR-030.
- Reduce cross-project variation where no project-specific requirement justifies
  it.

## Decision

The repository SHALL continue to maintain:

```text
doc/adr/README.intro.md
doc/adr/README.outro.md
doc/adr/*.md
```

The documentation build SHALL continue to generate:

```text
doc/adr/README.md
```

from the maintained framing and ADR corpus using the pinned adrctl dependency.

The generated `doc/adr/README.md` SHALL be ignored by Git and SHALL NOT be
committed as ordinary repository state.  It remains an inspectable local build
artifact and SHALL remain the Doxygen Markdown main page.

`make adr-index` SHALL retain its existing properties:

1. consume already-prepared `vendor/adrctl.bash` state;
2. remain offline;
3. derive ADR title/link enumeration through adrctl;
4. compose maintained framing around that generated enumeration;
5. write a same-directory candidate; and
6. replace the selected destination only after successful generation.

`make docs` SHALL continue to invoke `adr-index` before Doxygen and SHALL remain
offline after dependencies have been prepared.

`make docs-clean` SHALL remain focused on the generated Doxygen reference tree so
it does not race ADR index generation when Make executes prerequisites in
parallel.  A full generated-state cleanup such as `make distclean` SHALL remove
the generated ADR index as well as dependency state.

Doxygen SHALL exclude `README.intro.md` and `README.outro.md` as standalone input
pages.  Their content reaches the published site through the generated composite
main page.

Normal documentation generation SHALL continue to omit an ADR relationship graph
as required by ADR-030.

## Promises

1. The published Doxygen site continues to use a generated ADR landing page as its
   main page.
2. The landing page continues to contain the linked textual ADR index produced by
   adrctl.
3. Stable framing remains maintained source in `README.intro.md` and
   `README.outro.md`.
4. `doc/adr/README.md` is generated and ignored rather than committed.
5. ADR index generation remains atomic and offline after dependency preparation.
6. adrctl remains documentation-only tooling and remains outside bashlog consumer
   artifacts and runtime behavior.
7. Normal documentation generation remains free of an ADR relationship graph.

## Non-Promises

1. Browsing `doc/adr/` directly on GitHub is not promised to display the generated
   table of contents as a directory README.
2. The generated landing page is not an architectural source of truth.
3. This decision does not change public bashlog behavior or release artifacts.
4. This decision does not change the adrctl dependency version.
5. This decision does not restore, replace, or relocate the relationship graph
   removed by ADR-030.

## Adversary and Failure Model

The documentation trusted computing base is unchanged.  adrctl remains executable
documentation tooling whose pinned digest authorizes expected bytes but does not
prove behavioral safety.

Atomic candidate generation continues to protect against an ordinary generator
failure truncating the selected landing page.  Removing the generated README from
Git removes stale committed generated navigation as a repository failure mode.

The maintained ADRs and framing files remain the reviewable sources.  The
published site is reproducible from those sources plus prepared pinned tooling.

## Operational Constraints

- `doc/adr/README.intro.md` and `doc/adr/README.outro.md` MUST remain maintained
  source.
- `doc/adr/README.md` MUST be ignored and MUST NOT be committed as normal project
  state.
- `make adr-index` MUST continue to generate the selected ADR index atomically.
- `make adr-index` MUST remain offline and consume prepared adrctl state.
- `make docs` MUST continue to generate the ADR index before Doxygen.
- `make docs` MUST remain offline after repository dependencies are prepared.
- Doxygen MUST continue to use `doc/adr/README.md` as its main page.
- Doxygen SHOULD NOT publish the framing fragments as separate pages when their
  content is already present in the composite landing page.
- normal documentation generation MUST NOT invoke `adrctl generate graph`.
- adrctl MUST remain outside bashlog runtime and distributed artifacts.

## Considered Alternatives

### Keep the Generated README Committed

This preserves automatic GitHub directory rendering, but it also retains a
synchronization obligation for a derivative build input.  The published site is
the more important navigation surface, so this cost is no longer justified.

### Move the Generated File Outside `doc/adr/`

A build-only directory could make the generated nature even more explicit.  The
existing path already integrates cleanly with Doxygen and with adrctl's relative
links, however, so moving it would add churn without improving the ownership
boundary materially.

### Generate the Page Only in the Pages Workflow

This would keep local working trees cleaner, but it would make local `make docs`
produce a different documentation pipeline from CI publication.  The canonical
Make path should remain reproducible locally and in CI.

### Remove the Generated Landing Page Entirely

Doxygen could open directly into source-reference material.  That would recreate
the reader-experience problem the ADR landing page solved and was rejected.

## Consequences

The repository loses automatic GitHub rendering of a complete ADR directory
README.  Readers can use `doc/decisions.md` and individual ADRs in the repository,
while the published Doxygen site retains the complete generated landing page.

An ADR change no longer needs a mechanically generated README change in the same
commit.  Documentation generation remains deterministic and inspectable, while
source control contains only the maintained inputs.

The documentation model becomes consistent with bashdeps: maintained prose and
ADRs are source; generated navigation and HTML are build products.

## Superseded Decisions

This ADR supersedes only the retention portions of ADR-028 that require the
generated `doc/adr/README.md` to be committed and that cite GitHub directory
rendering as a requirement.  ADR-028's pinned adrctl dependency, configurable
index path, maintained framing, atomic replacement, and offline documentation
boundary remain in force.

This ADR also supersedes the portions of ADR-030 that explicitly reaffirm
ADR-028's committed-README requirement.  ADR-030's removal of normal relationship
graph generation remains fully in force.

## Related Decisions

- ADR-003: Make as the Canonical Orchestration Interface
- ADR-005: Dependency Management and Explicit Network Boundaries
- ADR-010: Generated Reference Documentation Is Ephemeral
- ADR-028: Generate Committed ADR Navigation with a Pinned adrctl Documentation Dependency
- ADR-030: Remove the Relationship Graph from Generated ADR Navigation
