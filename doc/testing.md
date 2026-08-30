# Testing

bashlog uses Bats for behavior-oriented tests and requires the same public
contract to hold across every shipped artifact flavor.  The goal is to validate
what consumers actually source rather than assume concatenation, comment
stripping, or minification cannot change behavior.

Prefer a larger number of focused tests over a small number of broad fixtures.  A
failing test should normally identify one primary contract, especially for
security-sensitive behavior where a broad scenario can hide which invariant was
actually violated.

## Active Contract Suite

The active bashlog public contract is implemented under `tests/contract/`.  These
tests are derived from the Accepted `doc/bashlog-spec.md` and ADR-013 through
ADR-024.

The Makefile runs every `tests/contract/*.bats` file against all three generated
artifacts:

```text
dist/bashlog.dev.bash
dist/bashlog.bash
dist/bashlog.min.bash
```

At the time the initial runtime implementation was established, the suite
contained 100 focused Bats tests per artifact, for 300 artifact-level results in
the normal CI matrix.

See [`tests/contract/README.md`](../tests/contract/README.md) for file-by-file
organization and fixture conventions.

## Contract Test Areas

The suite covers:

- source-time silence;
- preservation of traps, `set` options, and `shopt` options;
- caller ownership of generic function and alias names;
- absence of exported functions;
- documented namespaced API presence;
- representative operation with an unusable `PATH` to expose accidental runtime
  subprocess dependencies;
- canonical severity names and numeric mappings;
- default and boundary threshold behavior;
- exact `level: message` standard-error rendering;
- standard-output separation;
- printf-style formatting and logging option parsing;
- context validation before threshold suppression;
- threshold suppression before unnecessary printf-style message construction;
- context creation, append-only policy, destruction, and tombstones;
- fixed matching including overlap progression, adjacency, literal
  metacharacters, and empty replacement;
- exact multibyte fixed values including accented Latin, Cyrillic, CJK, emoji,
  and combining sequences;
- deliberate non-equivalence of distinct Unicode normalization forms;
- basic glob semantics and extglob rejection independent of ambient `shopt`;
- case-sensitive glob/ERE behavior even when caller `nocasematch` is enabled;
- preservation of caller `nocasematch` state;
- ERE validation, zero-length rejection, literal replacement, and anchored-match
  location against complete input;
- deterministic cross-matcher rule ordering;
- full rendered-record redaction, including severity labels;
- later replacements reintroducing earlier protected fixed/glob/ERE content;
- fail-closed final verification;
- fixed safe diagnostic behavior and suppression when the diagnostic itself
  violates active policy;
- negative assertions that protected originals never appear in standard output,
  standard error, or failure diagnostics;
- literal treatment of command-substitution and parameter-expansion text in
  replacements;
- and successful transformation behavior of `bashlog_redact` without an added
  newline.

This list should grow when implementation or review exposes a genuine missing
contract, not merely to increase test count.

## Child Bash Fixture Convention

Most behavior tests need to source one generated artifact in a clean child Bash
process and then exercise several operations in that same shell.

Pass those child programs on standard input:

```bash
run --separate-stderr bash --noprofile --norc -s -- "${BASHLOG_ARTIFACT}" <<'BASH'
  source "$1"
  bashlog_info 'value=%s' 'example'
BASH
```

Do not embed the program inside an outer single-quoted `bash -c '...'` string and
then use ordinary single-quoted Bash data inside it.  That nesting changes the
program before the child shell receives it and can create false failures or,
worse, false passes.

The literal heredoc approach preserves quotes, shell syntax intended as data,
Unicode fixtures, replacement text such as `$(...)` and `${...}`, and pattern
syntax exactly as the test author wrote them.

Tests using `run --separate-stderr` declare the appropriate minimum Bats version.

## Negative Security Assertions

For redaction, a positive assertion that the expected replacement appears is not
sufficient.

A test should also assert that the original protected value appears nowhere in
observable bashlog output.  Where relevant, that includes:

- standard output;
- standard error;
- safe failure diagnostics;
- output from every severity helper;
- transform-only redaction failures;
- and cross-rule failure paths.

The suite deliberately includes cases where an earlier replacement succeeds and a
later rule reintroduces content protected by an earlier rule.  Those cases must
still fail closed.  They demonstrate why successful substitution is not
equivalent to successful final verification.

## Artifact Equivalence

`make test` runs the same active public behavior suite against development,
ordinary, and minified artifacts.

`make test-report` repeats the same matrix and writes one JUnit XML report per
artifact flavor under `test-results/`.

A test that passes against one generated representation but fails against another
is a product defect.  Generated artifacts are public products, not incidental
build intermediates.

CI also removes `vendor/` after building and exercises representative public
behavior against every artifact.  This verifies that consumer runtime does not
depend on repository dependency state.

## Bash 4.3 Compatibility

Representative public behavior executes under Bash 4.3 while ADR-002 remains in
force.  Syntax validation alone is insufficient because runtime semantics around
arrays, substring operations, pattern matching, regular expressions, and shell
options are material to the redaction implementation.

`tests/contract/compat-bash43.bash` exercises at least:

- sourcing;
- level get/set;
- ordinary logging;
- fixed redaction;
- one glob rule;
- one ERE rule;
- context destruction;
- and one fail-closed final-verification interaction.

CI and release validation execute that compatibility program against each of the
three generated artifacts inside a Bash 4.3 container.

If a correct and auditable implementation can no longer satisfy the Accepted
contract on Bash 4.3, revisit ADR-002 rather than silently weakening either the
implementation or the tests.

## Matcher Regression Areas

### Anchored EREs

Bash exposes ERE matched text through `BASH_REMATCH` but does not provide a
portable match-offset API at the supported floor.  Searching for the first
literal occurrence of `BASH_REMATCH[0]` can select the wrong occurrence when an
anchored expression matches text identical to an earlier substring.

The suite therefore includes explicit `^` and `$` anchored ERE cases.  Any change
to ERE match-location logic should preserve these regression tests.

### `nocasematch`

Bash's `nocasematch` option affects both glob-style `[[ == ]]` comparisons and
ERE `[[ =~ ]]` matching.  bashlog's public matcher semantics are case-sensitive.
The suite therefore enables `nocasematch`, verifies that matching remains
case-sensitive, and verifies that the caller's enabled state is restored after
bashlog returns.

### Locale

Glob and ERE behavior uses the caller's locale where Bash/libc defines
locale-sensitive semantics.  Tests verify that bashlog does not mutate caller
locale while exercising both matcher types.

## Tooling Boundaries

Development tests may use external commands, temporary files, Docker, or other
ordinary test tooling.  ADR-014's no-external-command guarantee applies to the
consumer runtime, not the test harness.

The suite nevertheless launches a Bash process, replaces `PATH` with an unusable
value, and then exercises representative logging/redaction behavior.  Success
provides evidence that the runtime did not silently depend on `sed`, `awk`,
`grep`, `date`, `logger`, hashing tools, or other external commands.

Syntax validation and ShellCheck are part of `make check`, not substitutes for
behavior tests.  Doxygen generation validates documentation structure and
references, but it is likewise not proof of runtime behavior.

## Static Analysis

The Makefile keeps intentional ShellCheck exclusions narrow and module-specific.
The current exceptions correspond to documented architecture:

- SC2053: dynamic right-hand glob matching is the glob engine itself;
- SC2059: caller-supplied `printf` format strings are part of the public logging
  API;
- SC2154: modules consume global state declared in earlier modules in the explicit
  assembly order.

Do not turn these into broad repository-wide exclusions without architectural and
implementation justification.

## Release Verification

Release verification tests the exact generated bytes intended for publication,
verifies adjacent `.sha256` checksum companions, validates the three artifacts
with Bash syntax checks, runs the public behavior suite, runs the Bash 4.3
compatibility contract, and creates attestations only after validation succeeds.

Current release workflows do not publish `.256` companions for current artifacts.
Historical `.256` assets remain historical release data under ADR-012.
