# bashlog Contract Test Suite

This directory contains the red-phase behavior and security tests derived from
the accepted `doc/bashlog-spec.md` and ADR-013 through ADR-024.

The suite is intentionally **not** part of the current `tests/*.bats` Makefile
wildcard.  The repository still contains the starter runtime, and wiring these
tests into `make test` before the implementation exists would make the normal
project validation path fail by design.

The implementation phase should begin by:

1. replacing the non-runtime declaration bodies in `lib/level.bash`,
   `lib/logging.bash`, and `lib/redaction.bash` with real implementation;
2. changing the build source list from the starter plugin/CLI architecture to the
   sourceable bashlog module order established by the ADRs;
3. replacing the starter Bats suite with these contract tests or moving these
   files into the active `tests/*.bats` set;
4. setting `BASHLOG_ARTIFACT` for every generated artifact flavor; and
5. demonstrating that the same contract passes against development, ordinary,
   and minified artifacts.

These tests were written before the runtime implementation intentionally.  They
are executable statements of the accepted contract, not examples of current
implemented behavior.

## Test Organization

- `source-time.bats`: source-time silence, shell-state preservation, namespace,
  and runtime-command boundaries.
- `levels-and-logging.bats`: threshold semantics, severity helpers, formatting,
  rendering, streams, and call validation.
- `redaction-contexts.bats`: context creation, append-only lifecycle, destruction,
  and fail-closed context selection.
- `redaction-fixed.bats`: literal fixed matching, replacement semantics,
  occurrence behavior, and exact multibyte strings.
- `redaction-patterns.bats`: glob and ERE registration/matching semantics.
- `redaction-security.bats`: cross-rule reintroduction, final verification,
  diagnostics, complete-record coverage, and negative disclosure assertions.

## Test Environment

Each test expects:

```text
BASHLOG_ARTIFACT=/absolute/path/to/a/generated/bashlog.artifact
```

The artifact is sourced into a clean child Bash process.  The tests use Bats'
separate standard-output and standard-error capture because the public contract
assigns different meanings to those streams.

Development/test tooling may invoke external commands.  ADR-014's no-external-
command promise applies to the bashlog **consumer runtime**, not to the Bats test
harness.
