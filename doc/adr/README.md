# Architecture Decision Records

Architecture Decision Records preserve the reasoning behind consequential
technical and process decisions in this project.  They are intentionally more
verbose than operational summaries because context, alternatives, constraints,
and rejected options are part of the architectural record.

The repository uses a layered documentation model:

- ADRs explain why durable decisions exist and what constraints follow from
  them.
- `AGENTS.md` is a concise operational map that points back to the governing
  ADRs rather than repeating their reasoning.
- A project specification, when needed, describes current observable behavior.
- Doxygen comments preserve local implementation contracts and reasoning near
  the code that depends upon them.
- Tests and CI verify observable behavior and selected architectural invariants.

The ADR template includes an `Operational Constraints` section.  That section is
a compact representation of the decision for implementation and review; it does
not replace the surrounding rationale.

## Index

- ADR-000: Capability Scope, Epistemic Honesty, and Separation of Concerns
- ADR-001: Documentation and Decision Hierarchy
- ADR-002: Bash Runtime and Portability Baseline
- ADR-003: Make as the Canonical Orchestration Interface
- ADR-004: Modular Source Assembly and Automatically Discovered Plugins
- ADR-005: Dependency Management and Explicit Network Boundaries
- ADR-006: Three Release Artifact Flavors, Metadata, and Checksums
- ADR-007: Doxygen-Based Verbose Source Documentation Standard
- ADR-008: Documentation-Driven, Test-Second Development
- ADR-009: Observable Behavior Testing Across Shipped Artifacts
- ADR-010: Generated Reference Documentation Is Ephemeral
- ADR-011: Conventional-Commit Semantic Releases and Late Tagging
- ADR-012: Standardize SHA-256 Checksum Companion Filenames
