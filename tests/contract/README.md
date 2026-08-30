# bashlog Contract Test Suite

This directory contains the active behavior and security tests derived from the
Accepted `doc/bashlog-spec.md` and the governing ADR corpus, including the
presentation, adaptive-rendering, and severity-style decisions in ADR-025 through
ADR-027.

The suite is the executable public contract used by the Makefile, CI, and release
validation.  Implementation changes are expected to satisfy these tests; the
tests should not be weakened merely to make an implementation convenient.

## Artifact Matrix

The Makefile sets `BASHLOG_ARTIFACT` and executes the complete Bats suite against:

```text
dist/bashlog.dev.bash
dist/bashlog.bash
dist/bashlog.min.bash
```

All three artifacts must exhibit equivalent public behavior.

`make test-report` writes one JUnit report per artifact under `test-results/`.
The exact test count may grow as accepted behavior grows; the important invariant
is that every artifact receives the same complete contract suite.

## Test Organization

- `source-time.bats`: source-time silence, trap/shell/shopt preservation,
  namespace ownership, public API presence, and no-external-runtime-command
  evidence.
- `levels-and-logging.bats`: threshold semantics, canonical severity helpers,
  printf-style formatting, stream separation, option parsing, context validation
  order, and emission errors.  These tests force plain human rendering when the
  renderer is not the behavior under test.
- `presentation.bats`: presentation defaults and setters, adaptive non-TTY
  logfmt, explicit human/logfmt rendering, tags, global color boundaries,
  per-severity symbolic styles and resets, severity-token-only ANSI placement,
  timestamps, exact logfmt escaping, caller-managed and logger-managed redaction
  workflows, and final verification after rendering.
- `redaction-contexts.bats`: context creation, append-only lifecycle, destruction,
  tombstones, duplicate handling, and fail-closed context selection.
- `redaction-fixed.bats`: exact literal fixed matching, occurrence progression,
  literal replacements, empty replacement, multibyte strings, and explicit lack
  of Unicode normalization equivalence.
- `redaction-patterns.bats`: glob/ERE registration and matching semantics,
  extglob rejection, zero-length rejection, anchored ERE location, locale
  preservation, registration order, and `nocasematch` isolation.
- `redaction-security.bats`: cross-rule reintroduction, semantic-field primary
  redaction, post-render final verification, fixed safe diagnostics,
  replacement-as-data behavior, and negative disclosure assertions.  These tests
  force plain human rendering where presentation is not the contract under test.
- `compat-bash43.bash`: representative public behavior under Bash 4.3, including
  presentation configuration, severity style lookup/override/reset, exact styled
  human output, human/logfmt rendering, Bash-native timestamps, logging redaction,
  standalone redaction, context destruction, and fail-closed verification.

## Test Environment

Each Bats test expects:

```text
BASHLOG_ARTIFACT=/absolute/path/to/a/generated/bashlog.artifact
```

The artifact is sourced into a clean child Bash process.  Tests use Bats' separate
standard-output and standard-error capture because the public contract assigns
different meanings to those streams.

A Bats-captured stderr stream is not a TTY.  Therefore the actual default
`format=auto` behavior is logfmt in tests unless the test deliberately selects
`human`.  Tests whose purpose is levels or redaction rather than renderer choice
select `human` and `color=never` explicitly so they prove one contract at a time.

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
- logfmt escape fixtures;
- Unicode and combining-sequence fixtures;
- shell options configured inside the child process.

Do not replace this with a nested single-quoted `bash -c '...'` program containing
ordinary single-quoted Bash strings.  That quoting pattern can silently alter the
test program and produce misleading failures or accidental passes.

Additional test arguments may be passed after `BASHLOG_ARTIFACT`; they become
`$2`, `$3`, and so on inside the child program.  This is useful for keeping
security-test secret fixtures outside the program source while still preserving
their exact contents.

## Redaction Workflow Coverage

The suite treats both documented redaction workflows as first-class behavior.

Caller-managed redaction explicitly invokes:

```text
bashlog_redact CONTEXT STRING
```

and then logs the returned value without selecting the context again.

Logger-managed redaction explicitly supplies:

```text
--context CONTEXT
```

on the logging call.  In that path, the complete printf-style message and each
tag are transformed and verified before human/logfmt presentation, and the
completed rendered record is finally verified before emission.

Tests also prove the inverse: merely registering a context does not make it
ambient.  A logging call that omits `--context` is not inspected against unrelated
registered contexts.

## Presentation Style Coverage

Global color policy and per-level appearance are tested as separate dimensions.
`never|auto|always` decides whether human styling may be emitted; the level-style
API decides the foreground color and `normal|bold|dim` intensity of the canonical
severity token.

Tests verify the complete default palette, numeric/name equivalence, atomic
invalid setters, one-level and all-level reset behavior, and `default normal` as
a deliberately unstyled signifier.  Exact output assertions prove that the ANSI
reset immediately follows the severity token, so tags, punctuation, and message
text remain outside bashlog-owned styling.

The logfmt tests assert the complementary invariant: per-level style overrides and
`color=always` still produce no bashlog-owned ANSI in machine-oriented output.

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
closed at verification rather than emit the transformed-but-unsafe candidate.

Logger-managed tests also cover library-generated or renderer-generated text that
matches an explicitly selected context.  Primary redaction does not rewrite that
metadata; the final non-transforming check suppresses the completed record.

## Bash 4.3

`compat-bash43.bash` is intentionally smaller than the full Bats suite.  It is a
representative runtime compatibility contract covering sourcing, levels,
presentation configuration, severity style configuration/rendering,
human/logfmt rendering, timestamps, logging, fixed/glob/ERE redaction, context
destruction, and final fail-closed verification.

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
silently rely on ordinary external helpers during logging, presentation,
timestamp generation, or redaction.
