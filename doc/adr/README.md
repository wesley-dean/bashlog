# Architecture Decision Records

Architecture Decision Records preserve the reasoning behind consequential
technical and process decisions in this project.  They are intentionally more
verbose than operational summaries because context, alternatives, constraints,
promises, non-promises, failure models, and rejected options are part of the
architectural record.

The repository uses a layered documentation model:

- ADRs explain why durable decisions exist and what constraints follow from
  them.
- `doc/decisions.md` summarizes each decision in one to three sentences and links
  to the governing ADR.
- `AGENTS.md` is a concise operational map that points back to governing
  documentation rather than repeating its reasoning.
- A project specification, once created, describes current observable public
  behavior.
- Doxygen comments preserve local implementation contracts and reasoning near
  the code that depends upon them.
- Tests and CI verify observable behavior and selected architectural invariants.

The ADR template includes `Promises`, `Non-Promises`, `Adversary and Failure
Model`, and `Operational Constraints` sections.  Consequential ADRs should use
those sections when they make the decision boundary clearer.  The operational
constraints are a compact representation of the decision for implementation and
review; they do not replace the surrounding rationale.

See [`doc/decisions.md`](../decisions.md) for the concise current decision map.

## Index

### Accepted

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

### Proposed

- ADR-013: Sourceable Library Scope and Responsibility Boundary
- ADR-014: Pure Bash Runtime and External Command Boundary
- ADR-015: Namespaced Public API and Caller-Owned Convenience Wrappers
- ADR-016: Modular Source Assembly for a Sourceable Library
- ADR-017: Logging Pipeline, Levels, Formatting, and Emission
- ADR-018: Redaction as an Opt-In Security Boundary
- ADR-019: Readability, Auditability, and Rejection of Obscurity
- ADR-020: Redaction Context Lifecycle and State Model
- ADR-021: Redaction Rule Registration, Ordering, and Replacement Semantics
- ADR-022: Fixed-String Redaction and Multibyte Guarantees
- ADR-023: Glob and ERE Redaction Semantics
- ADR-024: Final Redaction Verification and Fail-Closed Output Boundary

## Templates

New ADRs should begin with [`templates/template.md`](templates/template.md).
The template intentionally encourages a "more is more" posture for consequential
decisions while allowing irrelevant optional sections to be removed when a
narrow decision genuinely does not need them.
