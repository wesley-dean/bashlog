# bashlog Contract Test Suite

This directory contains the active behavior and security tests derived from the
Accepted `doc/bashlog-spec.md` and ADR-013 through ADR-024.

The suite was intentionally written before the runtime implementation and is now
the executable public contract used by the Makefile, CI, and release validation.
Implementation changes are expected to satisfy these tests; the tests should not
be weakened merely to make an implementation convenient.

## Artifact Matrix

The Makefile sets `BASHLOG_ARTIFACT` and executes the complete Bats suite against:

```text
dist/bashlog.dev.bash
dist/bashlog.bash
dist/bashlog.min.bash
```

All three artifacts must exhibit equivalent public behavior.

`make test-report` writes one JUnit report per artifact under `test-results/`.
The initial implementation established 100 focused Bats tests per artifact, for
300 artifact-level test results in the normal matrix.

## Test Organization

- `source-time.bats`: source-time silence, trap/shell/shopt preservation,
  namespace ownership, public API presence, and no-external-runtime-command
  evidence.
- `levels-and-logging.bats`: threshold semantics, canonical severity helpers,
  printf-style formatting, rendering, stream separation, option parsing, context
  validation order, and emission errors.
- `redaction-contexts.bats`: context creation, append-only lifecycle, destruction,
  tombstones, duplicate handling, and fail-closed context selection.
- `redaction-fixed.bats`: exact literal fixed matching, occurrence progression,
  literal replacements, empty replacement, multibyte strings, and explicit lack
  of Unicode normalization equivalence.
- `redaction-patterns.bats`: glob/ERE registration and matching semantics,
  extglob rejection, zero-length rejection, anchored ERE location, locale
  preservation, registration order, and `nocasematch` isolation.
- `redaction-security.bats`: cross-rule reintroduction, final verification,
  fixed safe diagnostics, complete-record coverage, replacement-as-data behavior,
  and negative disclosure assertions.
- `compat-bash43.bash`: representative public behavior executed under Bash 4.3
  against each artifact by CI and release validation.

## Test Environment

Each Bats test expects:

```text
BASHLOG_ARTIFACT=/absolute/path/to/a/generated/bashlog.artifact
```

The artifact is sourced into a clean child Bash process.  Tests use Bats' separate
standard-output and standard-error capture because the public contract assigns
different meanings to those streams.

Tests using `--separate-stderr` declare the required minimum Bats version in
`setup()`.

## Child Program Convention

When a test needs a multi-command child Bash program, pass that program to
`bash -s` on standard input:

```bash
run --separate-stderr bash --noprofile --norc -s -- "${BASHLOG_ARTIFACT}" <<'BASH'
  source "$1"
  bashlog_info 'value=%s' 'example'
BASH
```

The quoted heredoc delimiter is intentional.  It ensures the Bats process does
not expand or reinterpret the child program before Bash under test receives it.
This is especially important for:

- single-quoted strings;
- replacement values containing `$(...)`, `${...}`, `&`, or backslashes;
- glob and ERE syntax;
- Unicode and combining-sequence fixtures;
- shell options configured inside the child process.

Do not replace this with a nested single-quoted `bash -c '...'` program containing
ordinary single-quoted Bash strings.  That quoting pattern can silently alter the
test program and produce misleading failures or accidental passes.

Additional test arguments may be passed after `BASHLOG_ARTIFACT`; they become
`$2`, `$3`, and so on inside the child program.  This is useful for keeping
security-test secret fixtures outside the program source while still preserving
their exact contents.

## Negative Security Assertions

Security tests should prove forbidden behavior did not occur, not only that an
expected replacement appeared.

For protected values, assert absence from the relevant observable channels:

- standard output;
- standard error;
- fixed failure diagnostics;
- every severity path;
- transform-only redaction failures;
- and cross-rule failure paths.

The suite deliberately contains cases where a later replacement recreates text
protected by an earlier fixed, glob, or ERE rule.  Those operations must fail
closed at final verification rather than emit the transformed-but-unsafe
candidate.

## Bash 4.3

`compat-bash43.bash` is intentionally smaller than the full Bats suite.  It is a
representative runtime compatibility contract covering sourcing, levels, logging,
fixed/glob/ERE redaction, context destruction, and final fail-closed verification.

CI and release validation execute it against all three generated artifacts inside
a Bash 4.3 container.

Compatibility failures should trigger investigation of the implementation and,
when necessary, explicit reconsideration of ADR-002.  Do not hide a runtime-floor
conflict by weakening the compatibility fixture.

## Tooling Boundary

Development/test tooling may invoke external commands, temporary files, Docker,
and other ordinary test infrastructure.  ADR-014's no-external-command promise
applies to the bashlog **consumer runtime**, not to Bats or CI itself.

The suite nevertheless includes representative runtime execution after `PATH` is
changed to an unusable value.  That test provides evidence that bashlog does not
silently rely on ordinary external helpers during logging/redaction.
