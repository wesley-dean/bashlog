# ADR-027: Configurable Severity Token Styles

Date: 2026-08-30

## Status

Proposed

## Intent and Documentation Posture

This Architecture Decision Record defines how callers may override the visual
style associated with each canonical bashlog severity while preserving the
presentation boundary established by ADR-025 and ADR-026.

The decision is intentionally narrow.  It governs only the appearance of the
canonical severity token in the human renderer.  It does not color timestamps,
tags, punctuation, or message bodies; it does not add ANSI to logfmt; and it does
not accept arbitrary caller-supplied escape sequences.

## Context

ADR-025 introduced terminal-sensitive color for human output and established a
library-owned default severity palette.  The implemented renderer currently
wraps only the canonical severity token in one ANSI SGR sequence and immediately
resets presentation state before tags or message text are appended.

That placement is desirable because the severity token is the visual signifier
that communicates record importance.  Coloring the complete log line would make
application data part of bashlog's presentation policy, create visually noisy
high-severity output, and enlarge the amount of caller-controlled text surrounded
by terminal control state.

The initial palette is also a policy choice rather than a universal truth.
Different applications, terminal themes, accessibility needs, and team conventions
may reasonably prefer different colors or intensity.  Callers therefore need a
controlled override mechanism without turning the library into an arbitrary ANSI
styling framework.

## Decision Drivers

- Preserve the established rule that bashlog-owned color decorates only the
  canonical severity token.
- Keep `bashlog_color_set never|auto|always` responsible only for whether human
  color styling is emitted.
- Allow callers to override the color and intensity associated with individual
  severity levels.
- Keep defaults useful without requiring configuration.
- Keep the API symbolic, readable, auditable, and Bash 4.3 compatible.
- Reject caller-supplied raw ANSI or arbitrary SGR fragments.
- Preserve logfmt as deterministic machine-oriented text with no bashlog-owned
  ANSI sequences.
- Preserve primary-redaction-before-presentation ordering.
- Keep invalid configuration atomic and side-effect free.

## Decision

bashlog SHALL make severity-token styling independently configurable from the
existing global color enablement policy.

The existing API remains:

```text
bashlog_color_get
bashlog_color_set MODE
```

where `MODE` is `never`, `auto`, or `always`.  These functions answer whether the
human renderer may emit bashlog-owned style sequences; they do not select the
style associated with a level.

The public API SHALL add:

```text
bashlog_level_style_get LEVEL
bashlog_level_style_set LEVEL COLOR INTENSITY
bashlog_level_style_reset [LEVEL]
```

### Severity Selection

`LEVEL` SHALL accept the same canonical severity names and numeric values already
accepted by `bashlog_level_set`:

```text
emergency | 0
alert     | 1
critical  | 2
error     | 3
warning   | 4
notice    | 5
info      | 6
debug     | 7
```

The style configuration is stored by canonical severity identity.  Numeric and
named references to the same level address the same style.

### Supported Colors

`COLOR` SHALL be exactly one of:

```text
default
black
red
green
yellow
blue
magenta
cyan
white
```

`default` means the terminal's ordinary foreground color.  It does not mean
"restore the bashlog default for this level"; restoring library defaults is the
responsibility of `bashlog_level_style_reset`.

The initial contract intentionally omits raw numeric SGR values, 256-color
indexes, RGB/true-color syntax, background colors, and terminal-specific names.
Those capabilities may be considered later if concrete use cases justify the
larger compatibility surface.

### Supported Intensity

`INTENSITY` SHALL be exactly one of:

```text
normal
bold
dim
```

The terms describe ANSI presentation requests rather than guaranteed physical
appearance.  Terminal emulators and themes may render bold or dim differently.

### Default Palette

The library defaults SHALL be:

| Severity | Color | Intensity |
| --- | --- | --- |
| `emergency` | `red` | `bold` |
| `alert` | `red` | `bold` |
| `critical` | `red` | `bold` |
| `error` | `red` | `normal` |
| `warning` | `yellow` | `normal` |
| `notice` | `cyan` | `normal` |
| `info` | `green` | `normal` |
| `debug` | `default` | `dim` |

The first three severities deliberately share bold red presentation because they
represent conditions more severe than an ordinary error.  Related severities are
allowed to share visual families; bashlog does not invent eight unrelated colors
merely because eight severity levels exist.

### Getter Semantics

```text
bashlog_level_style_get LEVEL
```

SHALL write exactly:

```text
COLOR INTENSITY
```

followed by one newline for the currently configured style of the selected
severity.

For example, before overrides:

```text
bashlog_level_style_get critical
red bold
```

The getter writes data to standard output and produces no routine standard-error
output.

### Setter Semantics

```text
bashlog_level_style_set LEVEL COLOR INTENSITY
```

SHALL atomically replace the selected level's style for subsequent human
rendering.

Examples:

```bash
bashlog_level_style_set error magenta bold
bashlog_level_style_set warning blue normal
bashlog_level_style_set debug default normal
```

An invalid level, color, intensity, or argument count SHALL return public usage
status `64`, produce no routine output, and leave the previous style unchanged.

### Reset Semantics

```text
bashlog_level_style_reset [LEVEL]
```

With one level argument, the function SHALL restore that severity's library
default style.

With no arguments, the function SHALL restore the complete default palette.

More than one argument or an invalid level SHALL return `64` and SHALL NOT alter
any style.

### Rendering Boundary

When human color is enabled by `bashlog_color_set`, bashlog SHALL apply the
configured style only to the canonical severity token.

Conceptually:

```text
[timestamp] STYLE_START severity STYLE_RESET [tag ...]: message
```

The following bytes SHALL remain outside bashlog-owned severity styling:

- optional timestamp;
- spaces and punctuation;
- tags;
- the colon separator;
- the formatted message;
- and the trailing newline emitted by the sink operation.

The reset sequence SHALL immediately follow the severity token whenever a style
sequence was emitted.

A style of `default normal` SHALL require no bashlog-owned SGR sequence.  This
allows a caller to leave one severity visually plain even while global color mode
is enabled.

### Interaction with Global Color Mode

Per-level style configuration does not override the global color policy.

```text
color=never
```

SHALL suppress all bashlog-owned severity styling regardless of per-level style.

```text
color=auto
```

SHALL use the configured per-level style only when the human renderer is active
and standard error is a TTY.

```text
color=always
```

SHALL use the configured per-level style whenever the human renderer is active,
even when human output is redirected.

The logfmt renderer SHALL never emit bashlog-owned ANSI styling regardless of
per-level style configuration or global color mode.

### Security and Redaction Ordering

Severity styling remains presentation decoration.  Logger-managed redaction SHALL
continue to transform and verify caller-supplied message and tag fields before
human rendering or ANSI decoration begins.

Per-level style configuration contains no caller message data and SHALL NOT be
processed by the redaction engine as semantic application content.  After
rendering, a context-protected record remains subject to the existing final
non-transforming verification boundary, including any bashlog-owned ANSI bytes
that are present.

## Promises

1. **Severity-token-only styling.**  bashlog-owned color and intensity affect only
   the canonical severity token in human output.
2. **Independent enablement and appearance.**  Global color mode decides whether
   style is emitted; per-level configuration decides what the token looks like.
3. **Useful defaults.**  Emergency, alert, and critical are bold red; error is
   red; warning yellow; notice cyan; info green; debug dim in the terminal default
   foreground.
4. **Caller override without raw ANSI.**  Applications can override symbolic
   foreground color and intensity without supplying escape sequences.
5. **Atomic configuration.**  Invalid style changes leave existing state intact.
6. **Resettable policy.**  One level or the full palette can be restored to
   library defaults.
7. **No ANSI in logfmt.**  Machine-oriented rendering remains free of
   bashlog-owned terminal styling.
8. **Redaction ordering is unchanged.**  Presentation styling cannot prevent
   primary redaction from seeing caller-supplied semantic values.

## Non-Promises

1. bashlog does not promise identical visual appearance across terminal
   emulators, themes, accessibility settings, or operating systems.
2. `bold` does not promise a brighter color, and `dim` does not promise a specific
   luminance reduction; those are terminal presentation semantics.
3. The initial style API does not provide background colors, underline, blink,
   reverse video, italics, arbitrary SGR attributes, 256-color indexes, or RGB
   color.
4. The initial style API does not accept raw ANSI or raw numeric SGR fragments.
5. Style configuration affects only future human-rendered records in the current
   Bash process and is not persisted by bashlog.
6. bashlog does not style arbitrary words appearing in the caller's message merely
   because they happen to equal a severity name.

## Adversary and Failure Model

This decision accounts for:

- a caller attempting to inject arbitrary terminal control sequences through
  presentation configuration;
- invalid configuration that must not partially change a style;
- applications whose accessibility or visual conventions differ from bashlog's
  defaults;
- redirected human output where the caller deliberately chose `color=always`;
- final-verification rules that may conservatively collide with renderer-owned
  ANSI bytes;
- and future maintainers tempted to expand a narrow severity-style API into a
  general terminal-formatting subsystem without a demonstrated requirement.

## Operational Constraints

- Styling MUST remain scoped to the canonical severity token.
- `bashlog_color_set` MUST remain the global enablement policy.
- Per-level style MUST NOT cause ANSI in logfmt output.
- Level selection MUST reuse the canonical severity normalization already used by
  the logging-level API.
- Supported colors MUST initially be `default`, `black`, `red`, `green`,
  `yellow`, `blue`, `magenta`, `cyan`, and `white`.
- Supported intensities MUST initially be `normal`, `bold`, and `dim`.
- Raw ANSI and arbitrary numeric SGR input MUST be rejected by API construction;
  callers are never asked to supply them.
- Invalid setters and resets MUST return `64` and leave prior state unchanged.
- `default normal` MUST emit no bashlog-owned style bytes for that severity.
- When style bytes are emitted, reset MUST immediately follow the severity token.
- Primary redaction MUST remain upstream of styling.
- Context-protected final verification MUST remain downstream of styling.
- Runtime implementation MUST remain pure Bash and compatible with Bash 4.3.

## Considered Alternatives

### Color the Entire Log Record

This would maximize visual prominence for warnings and failures.

It was rejected because it makes message data, tags, punctuation, and timestamps
part of the styling span.  High-severity messages become visually noisy, and the
presentation boundary becomes larger than necessary.  The canonical severity
word already communicates the classification clearly.

### Color Severity and Colon Together

This would make the signifier slightly larger while still avoiding the message.

It was rejected because the colon is renderer punctuation, not semantic severity.
Resetting immediately after the severity token creates the cleanest boundary and
keeps tags visually independent.

### Accept Raw ANSI / SGR Strings

This would provide maximum customization with very little library code.

It was rejected because it makes the caller responsible for correct terminal
state, permits arbitrary control bytes through a configuration API, complicates
validation and documentation, and weakens auditability.  Symbolic configuration
covers the intended use case while preserving a bounded contract.

### Provide One Monolithic Style String

For example:

```text
bashlog_level_style_set error "bold red"
```

This was rejected in favor of separate `COLOR` and `INTENSITY` arguments because
Bash already provides argument boundaries.  Separate tokens avoid introducing a
mini-parser, quoting rules, ordering questions, duplicate attributes, or
whitespace normalization into a small configuration API.

### Allow Arbitrary Attribute Lists

For example:

```text
bashlog_level_style_set error red bold underline blink
```

It was deferred because the current requirement is foreground color plus
boldness/intensity.  A general SGR attribute grammar would create substantially
more combinations and terminal-dependent behavior without a demonstrated need.

### Make Overrides Environment Variables

Environment variables could configure styles without additional public
functions.

It was rejected because sourced-library state should remain explicit, validated,
and process-local rather than acquiring implicit behavior from ambient variable
names.  Public functions also provide atomic validation and a discoverable
contract.

## Consequences

The human renderer gains a small amount of presentation state: one color and one
intensity per canonical severity.  The default visual behavior remains useful
without configuration, while applications can align the signifiers with local
conventions or accessibility needs.

Implementation will replace the fixed level-to-SGR mapping with readable
per-level symbolic state and a bounded symbolic-to-SGR encoder.  Tests must cover
all defaults, per-level overrides, numeric and named severity selection, atomic
invalid changes, single-level reset, full reset, `default normal`, global
`never|auto|always` interaction, severity-only ANSI placement, absence of ANSI in
logfmt, Bash 4.3 behavior, and context-protected final verification.

## Source Lineage

This decision extends ADR-025's human color feature without changing its
terminal-sensitive enablement policy and extends ADR-026's semantic-redaction-
before-presentation ordering without changing the universal stderr transport
boundary.

## Open Questions and Follow-Ups

- Bright ANSI foreground colors may be added later if a real accessibility or
  application-style requirement demonstrates value beyond ordinary colors plus
  independent intensity.
- Background colors and additional attributes remain intentionally outside the
  initial override API.

## Related Decisions

- ADR-002: Bash Runtime and Portability Baseline
- ADR-014: Pure Bash Runtime and External Command Boundary
- ADR-017: Logging Pipeline, Levels, Formatting, and Emission
- ADR-018: Redaction as an Opt-In Security Boundary
- ADR-019: Readability, Auditability, and Rejection of Obscurity
- ADR-024: Final Redaction Verification and Fail-Closed Output Boundary
- ADR-025: Optional Presentation Metadata, Tags, and Color
- ADR-026: Adaptive Human/Logfmt Rendering and Environment-Agnostic Stderr Transport
