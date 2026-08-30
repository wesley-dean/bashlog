# ADR-028: Generate Committed ADR Navigation with a Pinned adrctl Documentation Dependency

Date: 2026-08-30

## Status

Accepted

## Intent and Documentation Posture

This Architecture Decision Record defines how bashlog maintains the navigational
landing page for its ADR corpus.

The decision is intentionally about documentation architecture rather than
bashlog runtime behavior.  It establishes `adrctl` as a pinned documentation-only
dependency, makes `doc/adr/README.md` a generated but committed repository
surface, and keeps the generated index reproducible from maintained ADR source
plus small maintained introduction and conclusion fragments.

This ADR does not make `adrctl` a bashlog runtime dependency and does not add it to
any distributed bashlog artifact.

## Context

The ADR corpus is intentionally detailed and continues to grow.  A manually
maintained `doc/adr/README.md` duplicates titles and filenames already present in
the ADR documents, creating a predictable drift risk whenever an ADR is added,
renamed, or otherwise changes identity.

The project already uses generated documentation where generation adds value:
Doxygen converts maintained source comments into browsable reference material.
ADR-010 deliberately keeps that generated HTML ephemeral because it is a large,
redundant output tree that automation can reproduce when needed.

The ADR directory landing page has a different role.  GitHub renders
`doc/adr/README.md` automatically when a reader enters the directory, so the file
is useful precisely when it is present in the repository.  It is small, human-
reviewable Markdown and acts as repository navigation rather than a separately
published documentation site.

`adrctl` already understands the project's ADR filename/title model and provides
`generate toc` with optional introduction and conclusion files.  Reimplementing
that parsing in Make or another local script would create a second source of ADR
semantics.  Assuming an ambient `adrctl` installation would make documentation
output depend on untracked workstation or CI state.

The project already accepts pinned documentation dependencies such as the
bash-doxygen filter.  Using the same bashdeps-managed boundary for adrctl keeps the
dependency explicit, reviewable, checksum-pinned, and absent from consumer
runtime.

## Decision Drivers

- Remove mechanically duplicated ADR titles and filenames from maintained source.
- Keep `doc/adr/README.md` useful as the GitHub landing page for the ADR corpus.
- Reuse adrctl's ADR parsing/report semantics rather than reimplementing them.
- Keep documentation dependencies explicit and pinned rather than ambient.
- Preserve the existing offline `make docs` contract after dependencies are
  prepared.
- Keep adrctl outside all bashlog runtime and distribution artifacts.
- Preserve repository-specific explanatory prose around the generated index.
- Avoid replacing a valid committed README with partial output when generation
  fails.
- Leave room to compose additional adrctl report formats, including Mermaid graph
  output, without turning adrctl into a repository-layout engine.

## Decision

bashlog SHALL add the released `adrctl.bash` artifact as a pinned
bashdeps-managed repository dependency at:

```text
vendor/adrctl.bash
```

adrctl SHALL be treated as development/documentation tooling only.  It SHALL NOT
be concatenated, embedded, sourced, or otherwise included in
`dist/bashlog.dev.bash`, `dist/bashlog.bash`, or `dist/bashlog.min.bash`.

The Makefile SHALL expose a dedicated documentation target:

```text
make adr-index
```

`adr-index` SHALL:

1. require already-prepared `vendor/adrctl.bash` state;
2. invoke adrctl through Bash rather than relying on the dependency's executable
   mode;
3. run `generate toc` against the project's ADR corpus;
4. supply maintained introduction and conclusion fragments;
5. write the complete candidate README to a temporary same-directory path; and
6. replace `doc/adr/README.md` only after successful generation.

The maintained fragments SHALL live at:

```text
doc/adr/README.intro.md
doc/adr/README.outro.md
```

The generated and committed output SHALL live at:

```text
doc/adr/README.md
```

`make docs` SHALL invoke `adr-index` before generating Doxygen reference output.
It SHALL continue to consume prepared dependency state and SHALL NOT invoke
`make deps`, synchronize dependencies, or intentionally access the network.

The generated README SHALL be committed.  A change to the ADR corpus that changes
the generated index is therefore expected to include the corresponding
`doc/adr/README.md` update.

The maintained intro/outro fragments own repository-specific explanatory prose,
section headings, and other stable framing.  adrctl owns the mechanically derived
ADR title/link list.  Make owns composition, output placement, and atomic
replacement.

### Future Graph Composition

The initial implementation SHALL use the currently released adrctl TOC behavior.
When adrctl supports Mermaid graph serialization, bashlog MAY extend `adr-index`
to compose a Mermaid relationship graph into the same README.

That future addition SHOULD retain the same responsibility split:

```text
adrctl generate toc
    -> ADR index fragment

adrctl generate graph --format mermaid
    -> ADR relationship graph fragment

Make
    -> repository-specific Markdown composition and committed output
```

Mermaid support is not required by this ADR's initial implementation.

## Promises

1. `doc/adr/README.md` can be regenerated deterministically from the ADR corpus,
   maintained framing fragments, and the pinned adrctl dependency.
2. The generated README remains a committed repository navigation surface.
3. `make docs` remains offline after repository dependencies have been prepared.
4. adrctl remains outside bashlog consumer artifacts and runtime behavior.
5. Failure while generating the ADR index does not intentionally replace the
   prior README with partial output.
6. Repository-specific prose remains maintained source rather than being encoded
   inside adrctl.

## Non-Promises

1. This decision does not make the ADR README an independent architectural source
   of truth; the ADR documents remain authoritative.
2. This decision does not require generated Doxygen HTML to be committed.
3. This decision does not make adrctl available to bashlog consumers at runtime.
4. Pinning adrctl by SHA-256 does not prove adrctl is vulnerability-free or
   behaviorally trustworthy.
5. The initial implementation does not promise Mermaid graph output.
6. This decision does not require other projects to adopt adrctl as a documentation
   dependency merely because bashlog does so.
7. The generated index does not classify ADR status beyond whatever maintained
   framing the repository supplies around the generated list.

## Adversary and Failure Model

This decision considers:

- a stale hand-maintained index omitting or misnaming ADRs;
- a compromised or vulnerable adrctl dependency executing with documentation-
  build authority;
- substituted dependency bytes during acquisition;
- an unavailable or missing prepared adrctl dependency;
- adrctl generation failing after output has begun;
- a future adrctl release changing report semantics unexpectedly;
- repository-specific prose being lost because it was embedded in generated
  output instead of maintained separately;
- `make docs` accidentally acquiring dependencies or using the network; and
- documentation tooling accidentally becoming part of bashlog's consumer runtime.

Checksum pinning mitigates substituted acquisition bytes but does not establish
behavioral safety.  The dependency therefore remains part of the documentation
trusted computing base and should be reviewed accordingly.

Atomic same-directory candidate generation prevents an ordinary adrctl failure
from intentionally truncating the committed README.

## Operational Constraints

- adrctl MUST be pinned in `dependencies.txt` with an approved SHA-256 digest.
- adrctl MUST remain a documentation/development dependency only.
- bashlog distribution artifacts MUST NOT include adrctl bytes.
- `adr-index` MUST consume prepared dependency state and MUST NOT synchronize
  dependencies.
- `make docs` MUST remain offline after dependencies are prepared.
- `doc/adr/README.intro.md` and `doc/adr/README.outro.md` MUST remain maintained
  source.
- `doc/adr/README.md` MUST be generated atomically and committed.
- ADR title/link enumeration MUST come from adrctl rather than a second local
  parser.
- Doxygen reference output under `doc/reference/` MUST remain ephemeral as defined
  by ADR-010.

## Considered Alternatives

### Continue Maintaining `doc/adr/README.md` Manually

This avoids a new dependency but duplicates ADR titles and filenames in a place
that predictably drifts as the corpus changes.  It was rejected because the
mechanical portion of the document is exactly the kind of information a focused
report generator should own.

### Assume adrctl Is Installed on the Host

This avoids adding a manifest record.  It was rejected because the documentation
build would then depend on ambient developer/CI state, version selection would be
implicit, and reproducibility would weaken.

### Reimplement ADR Enumeration in Make or Bash

This could avoid the adrctl dependency.  It was rejected because bashlog would
then maintain its own ADR filename/title parsing semantics despite already having
a purpose-built tool that owns those semantics.

### Make `doc/adr/README.md` Ephemeral Like Doxygen HTML

This would minimize committed generated files.  It was rejected because GitHub
uses the README directly as the ADR directory's landing page.  The small committed
Markdown file has repository-navigation value that the large Doxygen output tree
does not.

### Have adrctl Generate the Complete Repository-Specific README Layout

This could reduce Makefile composition.  It was rejected because headings,
explanatory prose, graph placement, and other page-layout choices belong to the
repository.  adrctl should emit focused report fragments that compose through
ordinary text interfaces.

## Consequences

`dependencies.txt` gains one additional documentation tool and the documentation
trusted computing base expands accordingly.  Dependency review therefore applies
to adrctl just as it applies to bash-doxygen, Bash-Minifier, CI actions, and other
repository tooling.

`make docs` now has two documentation products with intentionally different
retention policies: a small committed ADR navigation page and an ephemeral
Doxygen reference tree.

Adding an ADR no longer requires hand-editing a duplicate title list.  Running
`make adr-index` or `make docs` regenerates the list and produces ordinary Git
diff evidence when the committed README is stale.

The maintained introduction and conclusion add two small source files, but they
make ownership clearer: prose is maintained; enumeration is generated.

## Source Lineage

The design follows bashlog's existing Make/dependency boundaries, the explicit
network separation in ADR-005, and the ephemeral Doxygen decision in ADR-010.
It also applies the engineering-philosophy principles that dependencies are fresh
attack surface, generated artifacts can be product surfaces, and higher-level
documents should be assembled from focused UNIX-style text producers.

The `adrctl generate toc -i ... -o ...` interface provides the concrete report
primitive used by this decision.

## Open Questions and Follow-Ups

- `wesley-dean/adrctl#15` tracks selectable graph serialization including Mermaid.
  After a release containing that feature is pinned, bashlog should consider
  extending `adr-index` with a relationship graph.
- If repeated projects adopt this pattern successfully, template-bash may later
  consider adrctl as a standard documentation dependency through a separate
  dependency/trust decision.

## Related Decisions

- ADR-003: Make as the Canonical Orchestration Interface
- ADR-005: Dependency Management and Explicit Network Boundaries
- ADR-008: Documentation-Driven, Test-Second Development
- ADR-010: Generated Reference Documentation Is Ephemeral
- ADR-019: Readability, Auditability, and Rejection of Obscurity
