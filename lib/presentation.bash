# shellcheck shell=bash
## @file lib/presentation.bash
## @brief Implements bashlog presentation configuration and text renderers.
## @details
## This module owns the presentation state introduced by ADR-025, ADR-026, and
## ADR-027: renderer selection, optional Bash-native timestamps, severity-aware
## human color, per-level severity-token style configuration, tag validation,
## human rendering, and the constrained logfmt renderer.
##
## Presentation is deliberately downstream of logging policy and redaction.  The
## logging module supplies semantic fields that are already protected when an
## explicit redaction context was selected.  This module serializes those fields;
## it does not discover secrets, choose redaction policy, inspect deployment
## infrastructure, or choose a transport.  The logger passes the descriptor
## selected by the destination to the presentation helpers.
##
## Automatic behavior is intentionally narrow.  `format=auto` and `color=auto`
## inspect only the selected Bash descriptor's TTY result (fd 2 for queues
## at enqueue time).  They do not infer systemd, Docker,
## Podman, containers, init systems, logging drivers, or other infrastructure.
## @see doc/bashlog-spec.md
## @see doc/adr/ADR-025-optional-presentation-metadata-tags-and-color.md
## @see doc/adr/ADR-026-adaptive-human-logfmt-rendering-and-stderr-transport.md
## @see doc/adr/ADR-027-configurable-severity-token-styles.md
## @see doc/adr/ADR-034-explicit-destinations-and-deferred-logging-queues.md

## @var __bashlog_format_mode
## @brief Active renderer mode: auto, human, or logfmt.
declare -g __bashlog_format_mode=auto

## @var __bashlog_timestamp_mode
## @brief Active timestamp mode: off, utc, or local.
declare -g __bashlog_timestamp_mode=off

## @var __bashlog_color_mode
## @brief Active human-color mode: never, auto, or always.
declare -g __bashlog_color_mode=auto

## @var __bashlog_level_style_colors
## @brief Per-severity symbolic foreground colors indexed by normalized level.
declare -ga __bashlog_level_style_colors=(red red red red yellow cyan green default)

## @var __bashlog_level_style_intensities
## @brief Per-severity symbolic intensities indexed by normalized level.
declare -ga __bashlog_level_style_intensities=(bold bold bold normal normal normal normal dim)

## @var __bashlog_resolved_format
## @brief Internal output slot containing the renderer selected for one call.
declare -g __bashlog_resolved_format=

## @var __bashlog_timestamp_value
## @brief Internal output slot containing one generated timestamp or an empty value.
declare -g __bashlog_timestamp_value=

## @var __bashlog_render_result
## @brief Internal output slot containing the completed rendered record.
declare -g __bashlog_render_result=

## @var __bashlog_logfmt_quoted_value
## @brief Internal output slot containing one quoted and escaped logfmt value.
declare -g __bashlog_logfmt_quoted_value=

## @var __bashlog_human_color_code_value
## @brief Internal output slot containing the selected ANSI SGR code.
declare -g __bashlog_human_color_code_value=

## @fn bashlog_format_get()
## @brief Writes the active renderer mode.
## @details
## Return the exact configured mode rather than the renderer that `auto` would
## choose for the current file descriptor state.
## @par Standard Output
## The active mode followed by one newline.
## @retval 0 The mode was written successfully.
## @retval 64 Arguments were supplied.
bashlog_format_get() {
  if (( $# != 0 )); then
    return 64
  fi

  printf '%s\n' "${__bashlog_format_mode}"
}

## @fn bashlog_format_set()
## @brief Changes the renderer-selection mode for subsequent logging calls.
## @details
## Accept exactly `auto`, `human`, or `logfmt`.  Invalid input leaves the prior
## mode unchanged and produces no output.
## @param mode Renderer mode: auto, human, or logfmt.
## @retval 0 The mode changed successfully.
## @retval 64 The argument count or mode is invalid.
bashlog_format_set() {
  if (( $# != 1 )); then
    return 64
  fi

  case $1 in
    auto | human | logfmt) __bashlog_format_mode=$1 ;;
    *) return 64 ;;
  esac

  return 0
}

## @fn bashlog_timestamp_get()
## @brief Writes the active timestamp mode.
## @par Standard Output
## The active mode followed by one newline.
## @retval 0 The mode was written successfully.
## @retval 64 Arguments were supplied.
bashlog_timestamp_get() {
  if (( $# != 0 )); then
    return 64
  fi

  printf '%s\n' "${__bashlog_timestamp_mode}"
}

## @fn bashlog_timestamp_set()
## @brief Changes timestamp generation for subsequent logging calls.
## @details
## `off` adds no bashlog-generated timestamp, `utc` generates an RFC3339-like UTC
## value with second precision, and `local` generates local time with a numeric
## UTC offset.  Generation uses Bash builtin printf time formatting only.
## @param mode Timestamp mode: off, utc, or local.
## @retval 0 The mode changed successfully.
## @retval 64 The argument count or mode is invalid.
bashlog_timestamp_set() {
  if (( $# != 1 )); then
    return 64
  fi

  case $1 in
    off | utc | local) __bashlog_timestamp_mode=$1 ;;
    *) return 64 ;;
  esac

  return 0
}

## @fn bashlog_color_get()
## @brief Writes the active human-color mode.
## @par Standard Output
## The active mode followed by one newline.
## @retval 0 The mode was written successfully.
## @retval 64 Arguments were supplied.
bashlog_color_get() {
  if (( $# != 0 )); then
    return 64
  fi

  printf '%s\n' "${__bashlog_color_mode}"
}

## @fn bashlog_color_set()
## @brief Changes severity-aware ANSI color policy for the human renderer.
## @details
## `never` disables bashlog-owned ANSI, `auto` uses the selected output
## descriptor (fd 2 for queued records), and `always` enables human styling.
## Logfmt output never receives bashlog-owned ANSI regardless of this setting.
## Per-level appearance is configured independently with
## `bashlog_level_style_set`.
## @param mode Color mode: never, auto, or always.
## @retval 0 The mode changed successfully.
## @retval 64 The argument count or mode is invalid.
bashlog_color_set() {
  if (( $# != 1 )); then
    return 64
  fi

  case $1 in
    never | auto | always) __bashlog_color_mode=$1 ;;
    *) return 64 ;;
  esac

  return 0
}

## @fn bashlog_level_style_get()
## @brief Writes the configured color and intensity for one severity token.
## @details
## LEVEL accepts the same canonical name or integer from 0 through 7 accepted by
## `bashlog_level_set`.  Numeric and named forms address the same stored style.
## @param level Canonical severity name or numeric severity from 0 through 7.
## @par Standard Output
## `COLOR INTENSITY` followed by exactly one newline on success.
## @par Standard Error
## No routine output.
## @retval 0 The style was written successfully.
## @retval 64 The argument count or level is invalid.
## @par Examples
## @code
## bashlog_level_style_get critical
## # red bold
## @endcode
bashlog_level_style_get() {
  local level_number

  if (( $# != 1 )); then
    return 64
  fi

  __bashlog_level_to_number "$1" || return 64
  # shellcheck disable=SC2154 # Declared by lib/level.bash earlier in assembly.
  level_number=${__bashlog_level_number}
  printf '%s %s\n' \
    "${__bashlog_level_style_colors[level_number]}" \
    "${__bashlog_level_style_intensities[level_number]}"
}

## @fn bashlog_level_style_set()
## @brief Overrides the symbolic color and intensity for one severity token.
## @details
## COLOR is one of `default`, `black`, `red`, `green`, `yellow`, `blue`,
## `magenta`, `cyan`, or `white`.  INTENSITY is one of `normal`, `bold`, or
## `dim`.  Validation is atomic: invalid input leaves the prior style unchanged.
## Raw ANSI and numeric SGR fragments are not accepted by this API.
## @param level Canonical severity name or numeric severity from 0 through 7.
## @param color Symbolic foreground color.
## @param intensity Symbolic intensity: normal, bold, or dim.
## @retval 0 The style was changed successfully.
## @retval 64 The argument count, level, color, or intensity is invalid.
## @par Examples
## @code
## bashlog_level_style_set error magenta bold
## bashlog_level_style_set debug default normal
## @endcode
bashlog_level_style_set() {
  local level_number
  local color
  local intensity

  if (( $# != 3 )); then
    return 64
  fi

  __bashlog_level_to_number "$1" || return 64
  # shellcheck disable=SC2154 # Declared by lib/level.bash earlier in assembly.
  level_number=${__bashlog_level_number}
  color=$2
  intensity=$3

  case ${color} in
    default | black | red | green | yellow | blue | magenta | cyan | white) ;;
    *) return 64 ;;
  esac

  case ${intensity} in
    normal | bold | dim) ;;
    *) return 64 ;;
  esac

  __bashlog_level_style_colors[level_number]=${color}
  __bashlog_level_style_intensities[level_number]=${intensity}
  return 0
}

## @fn bashlog_level_style_reset()
## @brief Restores one severity style or the complete palette to library defaults.
## @details
## With no arguments, restore all eight default styles.  With one LEVEL argument,
## restore only that severity.  Invalid input leaves all styles unchanged.
## @param level Optional canonical severity name or numeric severity from 0 through 7.
## @retval 0 The requested default style state was restored.
## @retval 64 More than one argument was supplied or LEVEL is invalid.
## @par Examples
## @code
## bashlog_level_style_reset error
## bashlog_level_style_reset
## @endcode
bashlog_level_style_reset() {
  local level_number

  if (( $# > 1 )); then
    return 64
  fi

  if (( $# == 0 )); then
    __bashlog_level_style_colors=(red red red red yellow cyan green default)
    __bashlog_level_style_intensities=(bold bold bold normal normal normal normal dim)
    return 0
  fi

  __bashlog_level_to_number "$1" || return 64
  # shellcheck disable=SC2154 # Declared by lib/level.bash earlier in assembly.
  level_number=${__bashlog_level_number}

  case ${level_number} in
    0 | 1 | 2)
      __bashlog_level_style_colors[level_number]=red
      __bashlog_level_style_intensities[level_number]=bold
      ;;
    3)
      __bashlog_level_style_colors[level_number]=red
      __bashlog_level_style_intensities[level_number]=normal
      ;;
    4)
      __bashlog_level_style_colors[level_number]=yellow
      __bashlog_level_style_intensities[level_number]=normal
      ;;
    5)
      __bashlog_level_style_colors[level_number]=cyan
      __bashlog_level_style_intensities[level_number]=normal
      ;;
    6)
      __bashlog_level_style_colors[level_number]=green
      __bashlog_level_style_intensities[level_number]=normal
      ;;
    7)
      __bashlog_level_style_colors[level_number]=default
      __bashlog_level_style_intensities[level_number]=dim
      ;;
    *) return 64 ;;
  esac

  return 0
}

## @fn __bashlog_tag_valid()
## @brief Validates one caller-supplied tag token using the documented ASCII grammar.
## @details
## A function-local C locale keeps `[A-Za-z0-9_.:-]+` explicitly ASCII without
## changing caller locale state.
## @param tag Proposed tag text.
## @retval 0 The tag is valid.
## @retval 1 The tag is invalid.
__bashlog_tag_valid() {
  local LC_ALL=C

  if (( $# != 1 )); then
    return 1
  fi

  [[ $1 =~ ^[A-Za-z0-9_.:-]+$ ]]
}

## @fn __bashlog_format_resolve()
## @brief Resolves the configured renderer for the current logging operation.
## @details
## `auto` chooses human for a TTY at the selected descriptor (fd 1 or fd 2),
## otherwise logfmt.  Deferred records observe fd 2 at enqueue time.
## @param fd Effective rendering descriptor, 1 or 2.
## @retval 0 A renderer was selected and stored in `__bashlog_resolved_format`.
## @retval 70 Internal presentation state is invalid.
__bashlog_format_resolve() {
  local fd=${1-}

  if [[ ${fd} != 1 && ${fd} != 2 ]]; then
    __bashlog_resolved_format=
    return 70
  fi

  case ${__bashlog_format_mode} in
    human | logfmt)
      __bashlog_resolved_format=${__bashlog_format_mode}
      ;;
    auto)
      if [[ -t ${fd} ]]; then
        __bashlog_resolved_format=human
      else
        __bashlog_resolved_format=logfmt
      fi
      ;;
    *)
      __bashlog_resolved_format=
      return 70
      ;;
  esac

  return 0
}

## @fn __bashlog_timestamp_utc()
## @brief Generates one UTC timestamp without changing caller timezone state.
## @details
## The function-local exported `TZ=UTC0` applies only while Bash builtin printf
## performs the UTC conversion.  Bash restores the caller's prior variable value
## and export state when the function-local variable leaves scope.  Omitting a
## time argument uses Bash 4.3's documented current-time `%(...)T` behavior.
## @retval 0 UTC timestamp generation succeeded.
## @retval 70 Bash builtin time formatting failed.
__bashlog_timestamp_utc() {
  local -x TZ=UTC0

  if ! printf -v __bashlog_timestamp_value '%(%Y-%m-%dT%H:%M:%SZ)T'; then
    __bashlog_timestamp_value=
    return 70
  fi

  return 0
}

## @fn __bashlog_timestamp_acquire()
## @brief Generates one optional Bash-native timestamp for an eligible log record.
## @details
## UTC generation delegates to a helper with function-local exported timezone
## state.  Local generation does not shadow or assign `TZ`, so it uses the
## caller's normal local-time environment without modifying it.  Both generated
## modes use the no-argument current-time form supported by the Bash 4.3 floor.
## @retval 0 A timestamp was generated or timestamping is disabled.
## @retval 70 Bash time formatting failed or internal state is invalid.
__bashlog_timestamp_acquire() {
  __bashlog_timestamp_value=

  case ${__bashlog_timestamp_mode} in
    off)
      return 0
      ;;
    utc)
      __bashlog_timestamp_utc
      return $?
      ;;
    local)
      if ! printf -v __bashlog_timestamp_value '%(%Y-%m-%dT%H:%M:%S%z)T'; then
        __bashlog_timestamp_value=
        return 70
      fi
      ;;
    *)
      return 70
      ;;
  esac

  return 0
}

## @fn __bashlog_human_color_code()
## @brief Encodes the configured symbolic style for one canonical severity.
## @details
## The style arrays contain symbolic foreground color plus symbolic intensity.
## This helper maps only those bounded values to ANSI SGR codes.  A configured
## `default normal` style intentionally produces an empty code, causing the human
## renderer to emit no bashlog-owned SGR bytes for that severity.
## @param level Canonical severity name.
## @par Standard Output
## No output; the code is written to `__bashlog_human_color_code_value`.
## @retval 0 A valid style was encoded, including a deliberately empty code.
## @retval 70 The severity or internal symbolic style state is invalid.
__bashlog_human_color_code() {
  local level_number
  local color
  local intensity
  local color_code=
  local intensity_code=

  if ! __bashlog_level_to_number "$1"; then
    __bashlog_human_color_code_value=
    return 70
  fi
  # shellcheck disable=SC2154 # Declared by lib/level.bash earlier in assembly.
  level_number=${__bashlog_level_number}
  color=${__bashlog_level_style_colors[level_number]}
  intensity=${__bashlog_level_style_intensities[level_number]}

  case ${color} in
    default) color_code= ;;
    black) color_code=30 ;;
    red) color_code=31 ;;
    green) color_code=32 ;;
    yellow) color_code=33 ;;
    blue) color_code=34 ;;
    magenta) color_code=35 ;;
    cyan) color_code=36 ;;
    white) color_code=37 ;;
    *)
      __bashlog_human_color_code_value=
      return 70
      ;;
  esac

  case ${intensity} in
    normal) intensity_code= ;;
    bold) intensity_code=1 ;;
    dim) intensity_code=2 ;;
    *)
      __bashlog_human_color_code_value=
      return 70
      ;;
  esac

  if [[ -n ${intensity_code} && -n ${color_code} ]]; then
    __bashlog_human_color_code_value="${intensity_code};${color_code}"
  else
    __bashlog_human_color_code_value="${intensity_code}${color_code}"
  fi

  return 0
}

## @fn __bashlog_human_color_enabled()
## @brief Determines whether the current human record should style its severity token.
## @param fd Effective rendering descriptor, 1 or 2.
## @retval 0 Styling may be emitted.
## @retval 1 Styling must not be emitted.
## @retval 70 Internal color state is invalid.
__bashlog_human_color_enabled() {
  local fd=${1-}

  if [[ ${fd} != 1 && ${fd} != 2 ]]; then
    return 70
  fi

  case ${__bashlog_color_mode} in
    never) return 1 ;;
    always) return 0 ;;
    auto)
      if [[ -t ${fd} ]]; then
        return 0
      fi
      return 1
      ;;
    *) return 70 ;;
  esac
}

## @fn __bashlog_logfmt_quote()
## @brief Quotes and escapes one value for bashlog's constrained logfmt profile.
## @details
## The result is always enclosed in double quotes.  Backslash, quote, tab,
## carriage return, and newline use conventional backslash escapes.  Remaining
## ASCII control bytes U+0001..U+001F and U+007F use `\u00XX`.  Bash cannot
## represent embedded NUL and therefore U+0000 remains outside the contract.
## Multibyte text is otherwise preserved as represented by Bash.
## @param value Value to serialize.
## @retval 0 The quoted value was written to `__bashlog_logfmt_quoted_value`.
__bashlog_logfmt_quote() {
  local value=${1-}
  local length=${#value}
  local result='"'
  local index
  local character
  local code
  local hex
  local control
  local encoded=0

  for ((index = 0; index < length; index++)); do
    character=${value:index:1}
    case ${character} in
      $'\\') result+="\\\\" ;;
      '"') result+="\\\"" ;;
      $'\t') result+="\\t" ;;
      $'\r') result+="\\r" ;;
      $'\n') result+="\\n" ;;
      *)
        encoded=0
        for ((code = 1; code < 32; code++)); do
          if (( code == 9 || code == 10 || code == 13 )); then
            continue
          fi
          printf -v hex '%02X' "${code}"
          printf -v control '%b' "\\x${hex}"
          if [[ ${character} == "${control}" ]]; then
            result+="\\u00${hex}"
            encoded=1
            break
          fi
        done
        if (( ! encoded )); then
          printf -v control '%b' '\x7F'
          if [[ ${character} == "${control}" ]]; then
            result+="\\u007F"
          else
            result+=${character}
          fi
        fi
        ;;
    esac
  done

  result+='"'
  __bashlog_logfmt_quoted_value=${result}
  return 0
}

## @fn __bashlog_render_human()
## @brief Renders semantic fields into the compact human representation.
## @details
## Arguments are LEVEL, TIMESTAMP, MESSAGE, TTY_FD, then zero or more TAG values.
## Style decorates only the severity token and resets before tag/message
## text is appended.  A configured `default normal` style emits no bashlog-owned
## SGR bytes even when global color mode permits styling.
## @param level Canonical severity.
## @param timestamp Generated timestamp or empty string.
## @param message Formatted caller message, already redacted when requested.
## @param fd Effective rendering descriptor (1 or 2).
## @param tags Zero or more caller tags, already redacted when requested.
## @retval 0 The rendered record was written to `__bashlog_render_result`.
## @retval 70 Presentation state is invalid.
__bashlog_render_human() {
  local level=$1
  local timestamp=$2
  local message=$3
  local fd=$4
  shift 4
  local candidate=
  local level_text=${level}
  local tag
  local color_status

  __bashlog_human_color_enabled "${fd}"
  color_status=$?
  if (( color_status == 70 )); then
    return 70
  fi
  if (( color_status == 0 )); then
    if ! __bashlog_human_color_code "${level}"; then
      return 70
    fi
    if [[ -n ${__bashlog_human_color_code_value} ]]; then
      level_text=$'\033['"${__bashlog_human_color_code_value}"$'m'"${level}"$'\033[0m'
    fi
  fi

  if [[ -n ${timestamp} ]]; then
    candidate="[${timestamp}] "
  fi
  candidate+="${level_text}"

  for tag in "$@"; do
    candidate+=" [${tag}]"
  done

  candidate+=": ${message}"
  __bashlog_render_result=${candidate}
  return 0
}

## @fn __bashlog_render_logfmt()
## @brief Renders semantic fields into bashlog's constrained logfmt representation.
## @details
## Arguments are LEVEL, TIMESTAMP, MESSAGE, then zero or more TAG values.  Field
## order is deterministic: optional `ts`, required `level`, repeated `tag`, and
## required `msg`.  Message values are always quoted.  Tags remain unquoted while
## they still satisfy the public ASCII tag grammar after optional redaction;
## otherwise they are quoted with the same encoder used for messages.  Per-level
## severity styles never affect this renderer.
## @param level Canonical severity.
## @param timestamp Generated timestamp or empty string.
## @param message Formatted caller message, already redacted when requested.
## @param tags Zero or more caller tags, already redacted when requested.
## @retval 0 The rendered record was written to `__bashlog_render_result`.
## @retval 70 Presentation state is invalid.
__bashlog_render_logfmt() {
  local level=$1
  local timestamp=$2
  local message=$3
  shift 3
  local candidate=
  local tag

  if [[ -n ${timestamp} ]]; then
    candidate="ts=${timestamp} "
  fi
  candidate+="level=${level}"

  for tag in "$@"; do
    if __bashlog_tag_valid "${tag}"; then
      candidate+=" tag=${tag}"
    else
      __bashlog_logfmt_quote "${tag}"
      candidate+=" tag=${__bashlog_logfmt_quoted_value}"
    fi
  done

  __bashlog_logfmt_quote "${message}"
  candidate+=" msg=${__bashlog_logfmt_quoted_value}"

  __bashlog_render_result=${candidate}
  return 0
}

## @fn __bashlog_render_record()
## @brief Selects and executes the renderer for the chosen destination.
## @details
## Arguments are LEVEL, TIMESTAMP, MESSAGE, TTY_FD, then optional TAG values.
## TTY_FD is 1 for immediate STDOUT and 2 for immediate STDERR or enqueuing;
## records are rendered once when logged, never again when the queue is flushed.
## @param level Canonical severity.
## @param timestamp Generated timestamp or empty string.
## @param message Formatted caller message.
## @param fd Effective rendering descriptor (1 or 2).
## @param tags Zero or more caller tags.
## @retval 0 Rendering completed in __bashlog_render_result.
## @retval 70 Renderer selection or rendering failed.
__bashlog_render_record() {
  local level=$1
  local timestamp=$2
  local message=$3
  local fd=$4
  shift 4

  if ! __bashlog_format_resolve "${fd}"; then
    return 70
  fi

  case ${__bashlog_resolved_format} in
    human) __bashlog_render_human "${level}" "${timestamp}" "${message}" "${fd}" "$@" ;;
    logfmt) __bashlog_render_logfmt "${level}" "${timestamp}" "${message}" "$@" ;;
    *) return 70 ;;
  esac
}
