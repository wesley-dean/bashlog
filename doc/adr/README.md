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
- `doc/bashlog-spec.md` defines the accepted normative observable public
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

* [ADR-000: Capability Scope, Epistemic Honesty, and Separation of Concerns](ADR-000-capability-scope-and-epistemic-honesty.md)
* [ADR-001: Documentation and Decision Hierarchy](ADR-001-documentation-and-decision-hierarchy.md)
* [ADR-002: Bash Runtime and Portability Baseline](ADR-002-bash-runtime-and-portability-baseline.md)
* [ADR-003: Make as the Canonical Orchestration Interface](ADR-003-make-as-canonical-orchestration-interface.md)
* [ADR-004: Modular Source Assembly and Automatically Discovered Plugins](ADR-004-modular-source-and-plugin-discovery.md)
* [ADR-005: Dependency Management and Explicit Network Boundaries](ADR-005-dependency-management-and-network-boundaries.md)
* [ADR-006: Three Release Artifact Flavors, Metadata, and Checksums](ADR-006-release-artifact-flavors-and-metadata.md)
* [ADR-007: Doxygen-Based Verbose Source Documentation Standard](ADR-007-doxygen-verbose-source-documentation.md)
* [ADR-008: Documentation-Driven, Test-Second Development](ADR-008-documentation-driven-test-second-development.md)
* [ADR-009: Observable Behavior Testing Across Shipped Artifacts](ADR-009-observable-behavior-testing.md)
* [ADR-010: Generated Reference Documentation Is Ephemeral](ADR-010-generated-reference-documentation.md)
* [ADR-011: Conventional-Commit Semantic Releases and Late Tagging](ADR-011-conventional-semver-and-late-tagging.md)
* [ADR-012: Standardize SHA-256 Checksum Companion Filenames](ADR-012-standardize-sha256-checksum-companion-filenames.md)
* [ADR-013: Sourceable Library Scope and Responsibility Boundary](ADR-013-sourceable-library-scope-and-responsibility-boundary.md)
* [ADR-014: Pure Bash Runtime and External Command Boundary](ADR-014-pure-bash-runtime-and-external-command-boundary.md)
* [ADR-015: Namespaced Public API and Caller-Owned Convenience Wrappers](ADR-015-namespaced-public-api-and-caller-owned-convenience-wrappers.md)
* [ADR-016: Modular Source Assembly for a Sourceable Library](ADR-016-modular-source-assembly-for-a-sourceable-library.md)
* [ADR-017: Logging Pipeline, Levels, Formatting, and Emission](ADR-017-logging-pipeline-levels-formatting-and-emission.md)
* [ADR-018: Redaction as an Opt-In Security Boundary](ADR-018-redaction-as-an-opt-in-security-boundary.md)
* [ADR-019: Readability, Auditability, and Rejection of Obscurity](ADR-019-readability-auditability-and-rejection-of-obscurity.md)
* [ADR-020: Redaction Context Lifecycle and State Model](ADR-020-redaction-context-lifecycle-and-state-model.md)
* [ADR-021: Redaction Rule Registration, Ordering, and Replacement Semantics](ADR-021-redaction-rule-registration-ordering-and-replacement.md)
* [ADR-022: Fixed-String Redaction and Multibyte Guarantees](ADR-022-fixed-string-redaction-and-multibyte-guarantees.md)
* [ADR-023: Glob and ERE Redaction Semantics](ADR-023-glob-and-ere-redaction-semantics.md)
* [ADR-024: Final Redaction Verification and Fail-Closed Output Boundary](ADR-024-final-redaction-verification-and-fail-closed-output.md)
* [ADR-025: Optional Presentation Metadata, Tags, and Color](ADR-025-optional-presentation-metadata-tags-and-color.md)
* [ADR-026: Adaptive Human/Logfmt Rendering and Environment-Agnostic Stderr Transport](ADR-026-adaptive-human-logfmt-rendering-and-stderr-transport.md)
* [ADR-027: Configurable Severity Token Styles](ADR-027-configurable-severity-token-styles.md)
* [ADR-028: Generate Committed ADR Navigation with a Pinned adrctl Documentation Dependency](ADR-028-generate-committed-adr-navigation-with-pinned-adrctl.md)

## Templates

New ADRs should begin with [`templates/template.md`](templates/template.md).
The template intentionally encourages a "more is more" posture for consequential
decisions while allowing irrelevant optional sections to be removed when a
narrow decision genuinely does not need them.
