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
