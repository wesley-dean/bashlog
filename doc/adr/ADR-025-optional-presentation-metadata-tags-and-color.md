# ADR-025: Optional Presentation Metadata, Tags, and Color

Date: 2026-08-30

## Status

Proposed

## Intent and Documentation Posture

This Architecture Decision Record defines the presentation metadata that bashlog
may add around a log message without expanding the library into a general host-
inspection framework or weakening its redaction boundary.

The decision covers three capabilities that were deliberately deferred from the
first implemented contract:

- Bash-native timestamps;
- caller-supplied tags or component labels;
- and severity-aware ANSI color for human-facing output.

ADR-026 separately defines how bashlog chooses between the human and logfmt
renderers.  This ADR owns the fields and presentation policy shared by those
renderers rather than the transport or environment-selection model.

## Context

The first functional bashlog contract intentionally emitted only:

```text
level: message
```

That made the initial logging and redaction pipeline small enough to define and
prove precisely.  With that core now implemented, several useful presentation
features can be added without changing bashlog's narrow purpose.

The features have different security and compatibility implications.
Caller-supplied tags are untrusted sink-bound data and must participate in
redaction.  Timestamps are library-generated metadata, but they still become part
of the emitted record.  ANSI color is presentation control data and must not
interfere with matcher semantics or appear in machine-oriented logfmt output.

The project therefore needs explicit configuration and ordering rather than
adding presentation bytes opportunistically inside the logger.

## Decision Drivers

- Keep all runtime behavior within Bash 4.3 and ADR-014's no-external-command
  guarantee.
- Provide a useful interactive default before the first public release.
- Keep machine-oriented output free of bashlog-owned ANSI decoration.
- Ensure caller-supplied tags participate in the same redaction obligation as
  message data.
- Avoid an arbitrary template language that would add parsing and escaping
  semantics before concrete use cases justify it.
- Keep timestamp acquisition late enough that threshold-suppressed messages do
  not perform unnecessary metadata work.
- Preserve caller locale, timezone, shell options, and `shopt` state.
- Keep generated metadata narrowly related to logging rather than inspecting the
  host for unrelated context.

## Decision

bashlog SHALL add optional timestamp and tag fields and SHALL add configurable
severity-aware color for the human renderer.

Timestamping remains disabled by default.  Tags remain explicit per logging call.
Color defaults to terminal-sensitive `auto` behavior.

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

When `utc` is selected, bashlog SHALL generate a Bash-native current-time value in
this form:

```text
YYYY-MM-DDTHH:MM:SSZ
```

When `local` is selected, bashlog SHALL generate a Bash-native local-time value in
this form:

```text
YYYY-MM-DDTHH:MM:SS+HHMM
```

The human renderer SHALL display an enabled timestamp in brackets before the
severity:

```text
[2026-08-30T18:40:00Z] warning: connection delayed
```

The logfmt renderer defined by ADR-026 SHALL represent the same logical timestamp
as the `ts` field:

```text
ts=2026-08-30T18:40:00Z level=warning msg="connection delayed"
```

Timestamp generation SHALL use Bash builtin time formatting and SHALL NOT invoke
`date` or another external program.  UTC formatting MAY use function-local
`TZ` state when required, but caller-visible timezone state MUST be preserved.

Timestamp acquisition SHALL occur only after API syntax, explicitly requested
redaction context validity, and severity threshold eligibility have been
established.

The initial timestamp contract does not include fractional seconds.

### Per-Call Tags

Every public logging call SHALL accept zero or more repeatable:

```text
--tag TAG
```

options before the `--` terminator and format string.

Tags SHALL preserve exact argument order.

The initial tag grammar SHALL be an explicitly ASCII token:

```text
[A-Za-z0-9_.:-]+
```

An empty tag, whitespace, brackets, control characters, or characters outside
that grammar SHALL be rejected with public usage status `64`.

The human renderer SHALL display tags in brackets between severity and the colon:

```text
info [database]: connected
warning [api] [retry]: request delayed
```

The logfmt renderer SHALL represent each tag as a repeated `tag` key in caller
order:

```text
level=warning tag=api tag=retry msg="request delayed"
```

Tags are caller-supplied sink-bound data.  Renderer selection and serialization
MUST NOT allow a tag to bypass the selected redaction context.  ADR-026 defines
the stronger cross-renderer invariant that reversible serialization cannot be
used as a substitute for redaction.

The initial extension SHALL NOT add ambient global tags.  Applications that want
a constant component label MAY define caller-owned wrappers, for example:

```bash
db_info() {
  bashlog_info --tag database "$@"
}
```

This preserves ADR-015's caller-owned convenience-wrapper model and avoids
another mutable global configuration surface.

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

Color is a property of the human renderer only.  The logfmt renderer SHALL never
contain bashlog-owned ANSI SGR sequences, even if color mode is `always`.

Within the human renderer:

- `never` SHALL emit no bashlog-owned ANSI color sequences;
- `auto` SHALL color only when standard error is currently a terminal according
  to Bash's `[[ -t 2 ]]` test;
- `always` SHALL request color regardless of whether human output is redirected.

bashlog SHALL NOT invoke `tput`, `tty`, `test`, or another external command to
determine whether color should be used.

Color SHALL be severity-aware and implemented with library-owned ANSI SGR
constants.  The exact initial palette belongs in `doc/bashlog-spec.md` when these
proposed decisions are ratified so tests can treat it as observable public
behavior.

Color is presentation decoration rather than message semantics.  ANSI bytes MUST
NOT be introduced at a point where they can prevent a registered redaction rule
from matching semantic caller data.  Context-protected human output SHALL also be
subject to an appropriate final non-transforming verification after bashlog-owned
presentation decoration is complete.

### Default Presentation Combination

Together with ADR-026, the intended default configuration is:

```text
format=auto
color=auto
timestamp=off
```

Therefore:

```text
interactive terminal:
warning [database]: connection delayed
```

with severity-aware color applied to the documented human portion, while:

```text
non-terminal stderr:
level=warning tag=database msg="connection delayed"
```

contains no bashlog-owned ANSI color.

The developer does not need to know whether non-terminal standard error is being
captured by systemd, Docker, Podman, cron, CI, an orchestrator, a redirected file,
or another consumer.

### Arbitrary Render Templates

This tranche SHALL NOT provide a caller-defined interpolation or template
language such as:

```text
%timestamp %level %tag %message
```

The supported fields and renderer modes are configurable, but their ordering,
keys, punctuation, and escaping remain library-defined.

A later ADR may add named layouts or a template language if concrete use cases
justify the additional compatibility, parsing, and security surface.

## Promises

1. **Useful interactive color by default.**  Human output on a terminal uses
   terminal-sensitive severity color without requiring caller configuration.

2. **No ANSI in machine output.**  The logfmt renderer never contains
   bashlog-owned color sequences.

3. **No external metadata helper.**  Timestamp generation and terminal detection
   use Bash facilities only.

4. **Tags remain protected data.**  Caller-supplied tags cannot escape the
   selected redaction obligation merely because they are metadata rather than
   message text.

5. **Threshold-suppressed calls remain cheap.**  A valid call suppressed by
   severity policy does not acquire a timestamp, construct the message, encode
   tags, or add presentation decoration.

6. **Caller shell state is preserved.**  Timestamp and terminal handling do not
   leave caller `TZ`, shell options, `shopt` options, or other caller-owned state
   changed.

7. **No ambient host metadata expansion.**  Adding timestamps and tags does not
   authorize automatic hostname, PID, Git, container, service, or orchestration
   discovery.

## Non-Promises

1. Color is not promised to look identical across terminal themes, emulators, or
   accessibility settings.  bashlog emits standard SGR requests; presentation is
   controlled by the terminal.

2. `auto` color does not attempt to infer whether a non-terminal consumer happens
   to understand ANSI.  Under the adaptive rendering model, non-terminal output
   is logfmt and therefore contains no bashlog-owned ANSI regardless.

3. Timestamp modes do not provide sub-second precision in this tranche.

4. Local timestamp formatting inherits the platform's timezone database and
   `strftime` behavior.  bashlog does not become a timezone database.

5. Tags are not arbitrary structured metadata.  They are ordered, constrained
   caller labels.

6. bashlog does not promise that caller message content itself lacks ANSI or
   other control characters.  Renderer encoding and log-injection behavior are
   governed separately by the selected renderer's contract.

7. The project does not promise a caller-defined rendering language.

8. Interactive terminal output is not promised to remain byte-for-byte identical
   to the first implementation because the selected default intentionally adds
   color before the first public release.  Callers requiring plain human output
   can select `color=never`.

## Adversary and Failure Model

This decision accounts for:

- a tag containing characters intended to break visual field boundaries;
- a protected value appearing in a tag rather than the message body;
- a redaction rule that interacts with generated timestamp text;
- a redaction rule that interacts with bashlog-owned ANSI bytes;
- an application whose standard error is a terminal for one invocation and
  redirected for another;
- a threshold-suppressed call that should avoid unnecessary metadata work;
- caller locale or timezone state that must not be left changed;
- and future maintainers tempted to introduce presentation bytes before the
  security boundary because doing so appears visually convenient.

The decision does not sanitize arbitrary caller message content by itself.  The
selected renderer and redaction pipeline define the exact behavior of message
serialization.

## Operational Constraints

- Timestamp mode MUST default to `off`.
- Color mode MUST default to `auto`.
- Tags MUST be explicit per logging call and MAY be repeated.
- Tags MUST match `[A-Za-z0-9_.:-]+` using an explicitly ASCII interpretation.
- Timestamp and tag data MUST participate in the selected redaction obligation.
- Color MUST apply only to the human renderer.
- Logfmt output MUST contain no bashlog-owned ANSI color sequences.
- `auto` human color MUST use Bash `[[ -t 2 ]]` rather than an external command.
- Timestamp generation MUST use Bash builtin facilities and MUST NOT invoke
  external `date`.
- New configuration setters MUST validate atomically and leave prior state
  unchanged on invalid input.
- No arbitrary caller-controlled render template is introduced by this ADR.
- Presentation serialization MUST NOT weaken the fail-closed redaction boundary.

## Considered Alternatives

### Default Color to `never`

This would preserve byte-for-byte terminal output and make color explicitly
opt-in.

It was rejected because this decision is being made before the first public
release.  `auto` gives interactive users useful severity color while avoiding
ANSI in the machine-oriented logfmt renderer.  Callers that need plain human
bytes retain an explicit `never` mode.

### Default Color to `always`

This would guarantee color whenever the human renderer is used.

It was rejected because explicitly forced human output may be redirected to a
file or another non-terminal consumer.  ANSI should not appear there unless the
caller deliberately chooses `always`.

### Allow Color in Logfmt

An explicit `always` setting could be interpreted as applying ANSI regardless of
renderer.

It was rejected because logfmt exists to provide deterministic machine-oriented
text.  ANSI control bytes undermine that goal.  Color configuration therefore
has intentionally renderer-scoped semantics.

### Allow Arbitrary Tag Text

Treating tags as unrestricted strings would maximize caller flexibility.

It was rejected because tags are metadata tokens, not a second message body.  A
small ASCII grammar keeps both human and logfmt rendering unambiguous.  Arbitrary
text belongs in the message.

### Add Global Mutable Tags

A persistent application or component tag would reduce repetition.

It was deferred because caller-owned wrapper functions already solve the common
case without another mutable global configuration layer.  A later ADR can add a
persistent tag model if repeated per-call tags prove materially burdensome.

### Require Callers to Supply Timestamps

This preserves the narrowest possible metadata-acquisition boundary.

It remains a valid caller pattern, but ADR-014 explicitly permits Bash-native time
metadata if separately adopted.  A standard optional timestamp is sufficiently
logging-specific, requires no external process, and improves consistency across
callers.

### Caller-Defined Render Templates

A template language would provide maximum customization.

It was deferred because it introduces parsing, escaping, invalid-template
behavior, security ordering, and a larger compatibility surface before concrete
requirements justify them.

## Consequences

The presentation model becomes richer while remaining narrow.  Interactive human
output gains useful color by default.  Non-terminal output receives no
bashlog-owned ANSI because ADR-026 selects logfmt there under the default format
mode.

Implementation will need explicit presentation state, additional option parsing,
Bash-native timestamp generation, tag validation, and renderer-aware color
application.

Tests must cover timestamps with redaction, tags containing protected values,
color in `never`/`auto`/`always` modes, terminal and redirected human output,
logfmt's unconditional no-color guarantee, invalid configuration, and
preservation of caller state.

## Source Lineage

This decision follows ADR-013's permission for narrowly scoped Bash-native
logging metadata, ADR-014's explicit allowance for Bash builtin time formatting,
ADR-015's caller-owned wrapper model, ADR-017's common logging pipeline, and
ADR-024's fail-closed final output boundary.

ADR-026 extends this presentation model by defining environment-agnostic standard-
error transport and adaptive human/logfmt renderer selection.

## Open Questions and Follow-Ups

- The exact ANSI SGR palette should be fixed in the normative specification when
  this ADR is accepted.
- Implementation should verify Bash 4.3 builtin timestamp formatting and
  function-local timezone handling in the compatibility environment.
- A future need for persistent/global component tags should be demonstrated
  before another mutable configuration layer is added.
- Structured fields beyond timestamp, level, tag, and message remain outside this
  ADR and require explicit review.

## Related Decisions

- ADR-002: Bash Runtime and Portability Baseline
- ADR-013: Sourceable Library Scope and Responsibility Boundary
- ADR-014: Pure Bash Runtime and External Command Boundary
- ADR-015: Namespaced Public API and Caller-Owned Convenience Wrappers
- ADR-017: Logging Pipeline, Levels, Formatting, and Emission
- ADR-018: Redaction as an Opt-In Security Boundary
- ADR-019: Readability, Auditability, and Rejection of Obscurity
- ADR-024: Final Redaction Verification and Fail-Closed Output Boundary
- ADR-026: Adaptive Human/Logfmt Rendering and Environment-Agnostic Stderr Transport
