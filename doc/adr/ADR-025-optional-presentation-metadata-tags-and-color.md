# ADR-025: Optional Presentation Metadata, Tags, and Color

Date: 2026-08-30

## Status

Proposed

## Intent and Documentation Posture

This Architecture Decision Record defines the first additive presentation layer
above bashlog's implemented minimal `level: message` renderer.  The project has
now proven the core logging and redaction contract across all generated artifact
forms and Bash 4.3.  Optional presentation features can therefore be considered
without using them to conceal uncertainty in the core design.

The decision favors useful defaults while remaining conservative about redirected
and service-oriented output.  Presentation features should make logs more useful
to humans without weakening redaction, expanding the external-command boundary,
or making the security-critical path difficult to reason about.

## Context

The first functional bashlog contract deliberately omitted timestamps, tags,
colors, host metadata, and other presentation features.  That omission made the
initial logging pipeline small enough to define and test precisely:

```text
level: message
```

That minimal contract is now implemented.  Several useful capabilities were
explicitly deferred rather than rejected permanently:

- severity-aware color for interactive use;
- caller-supplied tags or component labels;
- timestamps generated without invoking external `date`;
- and a controlled amount of configurable rendering decoration.

These features interact with the redaction boundary in different ways.
Caller-supplied tags are untrusted sink-bound text and therefore must be included
in redaction.  Timestamps are library-generated metadata but still become part of
the emitted record.  ANSI color is presentation control data rather than message
semantics and can interfere with pattern matching if inserted before redaction.

The project therefore needs an explicit ordering model rather than adding each
feature independently wherever it is easiest to implement.

## Decision Drivers

- Preserve the existing plain output form for redirected and non-terminal stderr
  unless the caller explicitly requests color.
- Provide a useful interactive default before the first public release rather
  than requiring every terminal user to discover and enable color manually.
- Keep all new runtime behavior within Bash 4.3 and the no-external-command
  guarantee of ADR-014.
- Ensure caller-supplied tags participate in the same redaction boundary as the
  message and severity label.
- Prevent ANSI escape sequences from changing the semantics of fixed, glob, or
  ERE redaction.
- Keep configuration explicit and inspectable rather than inferred from a large
  collection of environment variables.
- Avoid an arbitrary template language that would introduce another parsing and
  escaping surface.
- Keep redirected, CI, service, and persisted logs free of bashlog-owned ANSI
  decoration by default.
- Keep timestamp acquisition late enough that threshold-suppressed messages do
  not perform unnecessary metadata work.
- Preserve caller locale and shell state while generating metadata.

## Decision

bashlog SHALL add optional timestamp, tag, and color presentation capabilities.
Timestamping remains disabled by default and tags remain per-call opt-in.  Color
SHALL default to terminal-sensitive `auto` mode.

Therefore, with timestamp `off` and no tags:

- non-terminal standard error SHALL retain the existing `level: message` bytes;
- terminal standard error MAY include the documented bashlog-owned severity color
  decoration; and
- callers that require byte-for-byte plain terminal output MAY select color mode
  `never` explicitly.

### Timestamp Configuration

The public API SHALL add:

```text
bashlog_timestamp_get
bashlog_timestamp_set MODE
```

`MODE` SHALL be exactly one of:

```text
off
utc
local
```

The default SHALL be `off`.

When `utc` is selected, bashlog SHALL prepend a Bash-native current-time value in
this form:

```text
[YYYY-MM-DDTHH:MM:SSZ]
```

When `local` is selected, bashlog SHALL prepend a Bash-native local-time value in
this form:

```text
[YYYY-MM-DDTHH:MM:SS+HHMM]
```

The exact offset is produced by the platform's `strftime` implementation through
Bash builtin `printf`; the initial contract does not require insertion of a colon
into the numeric offset.

Timestamp generation SHALL use Bash builtin time formatting and SHALL NOT invoke
`date` or another external program.  UTC formatting MAY use a function-local
`TZ` value when required and MUST restore or preserve caller-visible timezone
state after the operation.

Timestamp acquisition SHALL occur only after syntax, explicitly requested
context validity, and threshold eligibility have been established.

### Per-Call Tags

Every public logging call SHALL accept zero or more repeatable:

```text
--tag TAG
```

options before the `--` terminator and format string.

Tags SHALL be rendered in the exact order supplied by the caller.  Each tag SHALL
be rendered as:

```text
[TAG]
```

For example:

```text
info [database]: connected
warning [api] [retry]: request delayed
```

The initial tag grammar SHALL be a deliberately boring ASCII token:

```text
[A-Za-z0-9_.:-]+
```

An empty tag, a tag containing whitespace, a tag containing brackets, or a tag
containing other characters outside this grammar SHALL be rejected with public
usage status `64`.

Tags are caller-supplied sink-bound data.  They SHALL be incorporated into the
plain semantic record before redaction transformation and final verification.
A redaction context may therefore transform or suppress content appearing in a
tag exactly as it may transform or suppress message or severity text.

The initial extension SHALL NOT add ambient global tags.  Applications that want
a constant component label MAY define a caller-owned wrapper:

```bash
db_info() {
  bashlog_info --tag database "$@"
}
```

This preserves the caller-owned convenience-wrapper model of ADR-015 and avoids
another mutable global configuration surface.

### Plain Semantic Rendering

Before color or other sink decoration, the rendered record SHALL use these forms:

```text
LEVEL: MESSAGE
LEVEL [TAG] [TAG]: MESSAGE
[TIMESTAMP] LEVEL: MESSAGE
[TIMESTAMP] LEVEL [TAG] [TAG]: MESSAGE
```

Only enabled fields appear.

The timestamp, canonical severity, tags, punctuation, and message together form
the semantic sink-bound candidate.  When a redaction context is selected, this
complete plain candidate SHALL pass through the existing ordered transformation
and final-verification boundary.

### Color Configuration

The public API SHALL add:

```text
bashlog_color_get
bashlog_color_set MODE
```

`MODE` SHALL be exactly one of:

```text
never
auto
always
```

The default SHALL be `auto`.

`never` SHALL emit no bashlog-owned ANSI color sequences.

`auto` SHALL color only when standard error is currently a terminal according to
Bash's `[[ -t 2 ]]` test.  bashlog SHALL NOT invoke `tput`, `tty`, `test`, or any
external command to determine terminal state.

`always` SHALL apply color regardless of whether standard error is a terminal.
This mode is intentionally explicit; callers choosing it accept that redirected
or persisted output may contain ANSI SGR bytes.

Color SHALL be severity-aware and implemented with library-owned ANSI SGR
constants.  The exact initial palette belongs in `doc/bashlog-spec.md` when this
ADR is accepted so that tests can treat it as observable public behavior.

Color SHALL be a presentation decoration, not part of matcher semantics.  The
plain semantic record SHALL be redacted and verified before ANSI decoration is
added.  If an active redaction context is selected, the decorated candidate SHALL
then be verified again before emission so library-added control bytes cannot
silently create a final candidate that violates an active rule.

The second verification is intentionally non-transforming.  bashlog SHALL NOT
rerun the transformation rule set after adding presentation decoration.

### Arbitrary Render Templates

The initial extension SHALL NOT provide a caller-defined interpolation/template
language such as:

```text
%timestamp %level %tag %message
```

The supported decorations themselves are configurable, but their ordering and
punctuation remain library-defined.  This keeps the redaction boundary, output
shape, and parsing rules finite and inspectable.

A later ADR may add named layouts or a template language if concrete use cases
justify the additional compatibility and security surface.

## Promises

1. **Redirect-safe default.**  With timestamp `off`, color `auto`, and no tags,
   non-terminal stderr retains the existing plain `level: message` output.

2. **Useful interactive default.**  When stderr is a terminal, the default `auto`
   mode may add the documented severity-aware ANSI color without requiring caller
   configuration.

3. **No external metadata helper.**  Timestamp generation and terminal detection
   use Bash facilities only.

4. **Tags are redacted as sink-bound data.**  Caller-supplied tags cannot bypass
   the complete-record redaction boundary.

5. **Color does not alter redaction matching semantics.**  Redaction transforms
   the plain semantic record before ANSI bytes are introduced.

6. **Decorated protected output is verified again.**  When a context is active,
   the final decorated candidate is checked before emission.

7. **Threshold-suppressed calls remain cheap.**  A valid call suppressed by
   severity policy does not acquire a timestamp, construct the message, or add
   presentation decoration.

8. **Caller shell state is preserved.**  Timestamp and terminal handling do not
   leave caller `TZ`, shell options, `shopt` options, or other caller-owned state
   changed.

## Non-Promises

1. Color is not promised to look identical across terminal themes, emulators, or
   accessibility settings.  bashlog emits standard SGR requests; presentation is
   controlled by the terminal.

2. `auto` does not attempt to infer whether a non-terminal consumer understands
   ANSI escapes.  It is intentionally based on `[[ -t 2 ]]` only.

3. Timestamp modes do not provide sub-second precision in the initial extension.

4. Local timestamp formatting inherits the platform's timezone database and
   `strftime` behavior.  bashlog does not become a timezone database.

5. Tags are not arbitrary structured metadata.  They are ordered display tokens
   with a constrained grammar.

6. bashlog does not promise that caller message content lacks ANSI or other
   control characters.  The existing contract continues to leave caller message
   normalization outside bashlog.

7. The project does not promise a caller-defined rendering language in this
   tranche.

8. Existing terminal output is not promised to remain byte-for-byte identical
   after this feature is adopted, because the selected default intentionally
   adds color when stderr is a terminal.  Callers requiring plain terminal bytes
   can select `never`.

## Adversary and Failure Model

This decision accounts for:

- a tag containing characters intended to break visual field boundaries;
- a protected value appearing in a tag rather than the message body;
- a redaction rule that intentionally or accidentally matches generated
  timestamp text;
- a redaction rule that matches a bashlog-owned ANSI byte sequence after
  decoration;
- an application running with standard error redirected to a file or journal;
- a threshold-suppressed call that contains expensive or invalid formatting
  arguments;
- caller locale or timezone state that must not be left changed;
- and future maintainers tempted to insert color before the security boundary
  because it is visually convenient.

The decision does not attempt to sanitize arbitrary control characters already
present in caller message data.  That remains a separately documented limitation
of the first public contract.

## Operational Constraints

- Timestamp default MUST be `off`.
- Color default MUST be `auto`.
- Tags MUST be explicit per logging call and MAY be repeated.
- Tags MUST match `[A-Za-z0-9_.:-]+` in an explicitly ASCII interpretation.
- Plain semantic rendering MUST occur before redaction.
- Timestamp and tag text MUST participate in redaction and final verification.
- ANSI color MUST NOT be inserted before the first redaction/final-verification
  boundary.
- Context-protected decorated output MUST receive a second non-transforming final
  verification before emission.
- `auto` color MUST use Bash terminal testing rather than an external command.
- `auto` color MUST emit no bashlog-owned ANSI sequences when stderr is not a
  terminal.
- Timestamp generation MUST use Bash builtin facilities and MUST NOT invoke
  external `date`.
- New configuration setters MUST validate atomically and leave prior state
  unchanged on invalid input.
- No arbitrary caller-controlled render template is introduced by this ADR.

## Considered Alternatives

### Default to `never`

This would preserve byte-for-byte terminal output across an upgrade and make all
color explicitly opt-in.

It was rejected because this work is occurring before the first public release,
when the project can still choose the more useful default without breaking an
established stable consumer contract.  `auto` gives interactive users useful
severity color while continuing to emit plain bytes when stderr is redirected.
Callers that require plain terminal output have an explicit `never` mode.

### Default to `always`

This would make presentation deterministic regardless of file-descriptor type and
would guarantee that terminal users see color.

It was rejected because ANSI bytes would then appear in files, CI captures,
service logs, and other non-terminal sinks unless every caller remembered to turn
color off.  That is a poor library default.

### Color Only the Severity Word Before Redaction

Coloring the level token before redaction would make implementation straightforward
because the token location is known before transformation.

It was rejected because ANSI bytes inserted into the semantic candidate would
change fixed/glob/ERE matching over the complete record and could prevent a rule
from matching text it protected before color was enabled.

### Allow Arbitrary Tag Text

Treating tags as unrestricted strings would maximize caller flexibility.

It was rejected because tags are presentation delimiters, not a second message
body.  A small ASCII token grammar keeps the rendering unambiguous.  Arbitrary
text belongs in the message and can still be protected by redaction.

### Add Global Mutable Tags

A persistent component/application tag would reduce repetition.

It was deferred because caller-owned wrapper functions already solve the common
case without adding mutable global configuration.  If repeated per-call tags
prove materially burdensome, a later ADR can add a global tag layer with explicit
override semantics.

### Caller-Defined Render Templates

A template language would provide maximum customization.

It was deferred because it would add parsing, escaping, invalid-template behavior,
and a larger compatibility surface before concrete requirements justify them.
Named optional decorations satisfy the current use cases while preserving a
small, auditable renderer.

### Require Callers to Supply Timestamps

This preserves the narrowest possible acquisition boundary.

It remains a valid caller pattern, but ADR-014 explicitly permits Bash-native time
metadata if separately adopted.  A standard opt-in timestamp is sufficiently
logging-specific, requires no external process, and improves consistency across
callers.

## Consequences

The renderer becomes richer.  Redirected/non-terminal output remains plain by
default, while interactive stderr gains severity-aware color unless the caller
selects `never`.  This is an intentional pre-release behavior choice rather than
an accidental compatibility change.

Implementation will need explicit presentation state, additional option parsing,
and a second final-verification step for protected output after decoration.

The second verification is intentional defense in depth.  It slightly increases
work for protected colored records, but it preserves the simple sink invariant
that the bytes bashlog ultimately emits have been checked against the selected
context after all bashlog-owned decoration is complete.

Tests must cover every combination that materially changes the boundary,
including timestamps with redaction, tags containing protected text, color in
`never`/`auto`/`always` modes, terminal and redirected standard error, invalid
tag/configuration input, and post-decoration verification.

## Source Lineage

This decision follows ADR-013's permission for narrowly scoped Bash-native
logging metadata, ADR-014's explicit allowance for Bash builtin time formatting,
ADR-017's common logging pipeline, and ADR-024's requirement that all sink-bound
content satisfy the final redaction boundary.

It also preserves the project's established preference for explicit
configuration, caller-owned convenience wrappers, and clean non-terminal output.

## Open Questions and Follow-Ups

- The exact ANSI SGR palette should be fixed in the normative specification when
  this ADR is accepted.
- Implementation should verify Bash 4.3 behavior for builtin timestamp formatting
  and function-local `TZ` handling on the compatibility image.
- A future need for persistent/global component tags should be demonstrated
  before adding another mutable configuration layer.
- Structured logging formats such as JSON remain outside this ADR and would
  require their own rendering and escaping decision.

## Related Decisions

- ADR-002: Bash Runtime and Portability Baseline
- ADR-013: Sourceable Library Scope and Responsibility Boundary
- ADR-014: Pure Bash Runtime and External Command Boundary
- ADR-015: Namespaced Public API and Caller-Owned Convenience Wrappers
- ADR-017: Logging Pipeline, Levels, Formatting, and Emission
- ADR-018: Redaction as an Opt-In Security Boundary
- ADR-019: Readability, Auditability, and Rejection of Obscurity
- ADR-024: Final Redaction Verification and Fail-Closed Output Boundary
