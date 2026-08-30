# Testing

bashlog uses Bats for behavior-oriented tests and requires the same public
contract to hold across every shipped artifact flavor.  The goal is to validate
what consumers actually source rather than assume concatenation, comment
stripping, or minification cannot change behavior.

Prefer a larger number of focused tests over a small number of broad fixtures.  A
failing test should normally identify one primary contract, especially for
security-sensitive behavior where a broad scenario can hide which invariant was
actually violated.

## Current Pre-Implementation State

The repository still contains the executable test suite inherited from
`template-bash`.  Those tests exercise the starter CLI, plugin registry, noop
plugin, generated artifacts, and checksum behavior.  They remain active only
because the bashlog runtime has not yet replaced the starter implementation.

The accepted bashlog public contract is represented by red-phase tests under
`tests/contract/` before implementation.  These tests are derived from the
accepted `doc/bashlog-spec.md` and ADR-013 through ADR-024.

The contract tests are **not** currently matched by the Makefile's top-level
`tests/*.bats` wildcard.  This is deliberate: accepting and merging a
pre-implementation contract should not make every ordinary repository validation
run fail merely because the implementation has not started.

The implementation phase should begin by activating this contract suite and
removing or replacing the starter behavior tests.  The implementation then earns
its way to green by satisfying the already-reviewed contract rather than writing
tests around whatever code happens to be produced.

See [`tests/contract/README.md`](../tests/contract/README.md) for the activation
sequence and file-by-file organization.

## Contract Test Areas

The dormant bashlog contract suite covers:

- source-time silence;
- preservation of traps, `set` options, and `shopt` options;
- caller ownership of generic function and alias names;
- documented namespaced API presence;
- representative operation with an unusable `PATH` to expose accidental runtime
  subprocess dependencies;
- canonical severity names and numeric mappings;
- default and boundary threshold behavior;
- exact `level: message` standard-error rendering;
- standard-output separation;
- printf-style formatting and option parsing;
- context validation before threshold suppression;
- context creation, append-only policy, destruction, and tombstones;
- fixed matching including overlap progression, adjacency, and literal
  metacharacters;
- exact multibyte fixed values including accented Latin, Cyrillic, CJK, emoji,
  and combining sequences;
- deliberate non-equivalence of distinct Unicode normalization forms;
- basic glob semantics and extglob rejection independent of ambient `shopt`;
- ERE validation, zero-length rejection, and literal replacement behavior;
- deterministic cross-matcher rule ordering;
- full rendered-record redaction, including severity labels;
- later replacements reintroducing earlier protected fixed/glob/ERE content;
- fail-closed final verification;
- fixed safe diagnostic behavior and suppression when the diagnostic itself
  violates active policy;
- negative assertions that protected originals never appear in standard output,
  standard error, or failure diagnostics;
- and successful transformation behavior of `bashlog_redact` without an added
  newline.

This list should grow when implementation exposes a genuine missing contract, not
merely to increase test count.

## Negative Security Assertions

For redaction, a positive assertion that the expected replacement appears is not
sufficient.

A test should also assert that the original protected value appears nowhere in
observable bashlog output.  Where relevant, that includes:

- standard output;
- standard error;
- safe failure diagnostics;
- output from every severity helper;
- and cross-rule failure paths.

The suite deliberately includes cases where the expected replacement operation
occurs and a later rule reintroduces content protected by an earlier rule.  Those
cases must still fail closed.  They demonstrate why successful substitution is
not equivalent to successful final verification.

## Artifact Equivalence

Once the bashlog runtime is implemented, `make test` SHALL run the active public
behavior suite against:

- `dist/bashlog.dev.bash`;
- `dist/bashlog.bash`; and
- `dist/bashlog.min.bash`.

`make test-report` SHALL repeat the same contract and write JUnit XML under
`test-results/` for CI reporting.

A test that passes against maintained fragments but fails against the minified
consumer artifact is a product defect.  Generated artifacts are public products,
not incidental build intermediates.

## Bash 4.3 Compatibility

Representative public behavior must also execute under Bash 4.3 while ADR-002
remains in force.  Syntax validation alone is insufficient because runtime
semantics around arrays, matching, and parameter expansion are part of the
redaction implementation risk.

The compatibility suite should exercise at least:

- sourcing;
- level get/set;
- ordinary logging;
- fixed redaction;
- one glob rule;
- one ERE rule;
- context destruction;
- and one fail-closed final-verification case.

If a correct and auditable implementation cannot satisfy the contract on Bash
4.3, the project should revisit ADR-002 rather than silently weakening either the
implementation or the tests.

## Tooling Boundaries

Development tests may use external commands, temporary files, Docker, or other
ordinary test tooling.  ADR-014's no-external-command guarantee applies to the
consumer runtime, not the test harness.

A useful runtime-boundary test is nevertheless to launch a Bash process first,
replace `PATH` with an unusable value, and then source and exercise bashlog.  A
representative path that still succeeds provides evidence that bashlog did not
silently depend on `sed`, `awk`, `grep`, `date`, `logger`, hashing tools, or other
external commands.

Syntax validation and ShellCheck are part of `make check`, not substitutes for
behavior tests.  Documentation generation is likewise verification of source
contracts, not proof of runtime behavior.

## Release Verification

Release verification must test the exact generated bytes intended for
publication, verify adjacent `.sha256` checksum companions, and preserve the
Bash 4.3 compatibility contract.

The starter-specific assertions about plugin discovery and noop execution should
be removed when the implementation replaces the starter architecture; they are
not bashlog product requirements.
