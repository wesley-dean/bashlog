# shellcheck shell=bash
## @file lib/presentation.bash
## @brief Implements bashlog presentation configuration and text renderers.
## @details
## This module owns the presentation state introduced by ADR-025 and ADR-026:
## renderer selection, optional Bash-native timestamps, severity-aware human
## color, tag validation, human rendering, and the constrained logfmt renderer.
##
## Presentation is deliberately downstream of logging policy and redaction.  The
## logging module supplies semantic fields that are already protected when an
## explicit redaction context was selected.  This module serializes those fields;
## it does not discover secrets, choose redaction policy, inspect deployment
## infrastructure, or choose a transport other than the caller-provided standard
## error stream.
##
## Automatic behavior is intentionally narrow.  `format=auto` and `color=auto`
## inspect only Bash's `[[ -t 2 ]]` result.  They do not infer systemd, Docker,
## Podman, containers, init systems, logging drivers, or other infrastructure.
## @see doc/bashlog-spec.md
## @see doc/adr/ADR-025-optional-presentation-metadata-tags-and-color.md
## @see doc/adr/ADR-026-adaptive-human-logfmt-rendering-and-stderr-transport.md

## @var __bashlog_format_mode
## @brief Active renderer mode: auto, human, or logfmt.
declare -g __bashlog_format_mode=auto

## @var __bashlog_timestamp_mode
## @brief Active timestamp mode: off, utc, or local.
declare -g __bashlog_timestamp_mode=off

## @var __bashlog_color_mode
## @brief Active human-color mode: never, auto, or always.
declare -g __bashlog_color_mode=auto

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
## `never` disables bashlog-owned ANSI, `auto` enables it only when fd 2 is a
## terminal, and `always` enables it whenever the human renderer is selected.
## Logfmt output never receives bashlog-owned ANSI regardless of this setting.
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
## `auto` means exactly TTY stderr -> human, otherwise logfmt.  No environment,
## process, filesystem, service-manager, or container detection occurs.
## @retval 0 A renderer was selected and stored in `__bashlog_resolved_format`.
## @retval 70 Internal presentation state is invalid.
__bashlog_format_resolve() {
  case ${__bashlog_format_mode} in
    human | logfmt)
      __bashlog_resolved_format=${__bashlog_format_mode}
      ;;
    auto)
      if [[ -t 2 ]]; then
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
## and export state when the function-local variable leaves scope.
## @retval 0 UTC timestamp generation succeeded.
## @retval 70 Bash builtin time formatting failed.
__bashlog_timestamp_utc() {
  local -x TZ=UTC0

  if ! printf -v __bashlog_timestamp_value '%(%Y-%m-%dT%H:%M:%SZ)T' -1; then
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
## caller's normal local-time environment without modifying it.
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
      if ! printf -v __bashlog_timestamp_value '%(%Y-%m-%dT%H:%M:%S%z)T' -1; then
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
## @brief Selects the ANSI SGR code for one canonical severity.
## @details
## The initial palette colors only the severity token: emergency/alert use bold
## red, critical/error red, warning yellow, notice cyan, info green, and debug dim.
## @param level Canonical severity name.
## @par Standard Output
## No output; the code is written to `__bashlog_human_color_code_value`.
## @retval 0 A code was selected.
## @retval 70 The severity is invalid.
__bashlog_human_color_code() {
  case $1 in
    emergency | alert) __bashlog_human_color_code_value='1;31' ;;
    critical | error) __bashlog_human_color_code_value='31' ;;
    warning) __bashlog_human_color_code_value='33' ;;
    notice) __bashlog_human_color_code_value='36' ;;
    info) __bashlog_human_color_code_value='32' ;;
    debug) __bashlog_human_color_code_value='2' ;;
    *)
      __bashlog_human_color_code_value=
      return 70
      ;;
  esac

  return 0
}

## @fn __bashlog_human_color_enabled()
## @brief Determines whether the current human record should color its severity token.
## @retval 0 Color should be emitted.
## @retval 1 Color should not be emitted.
## @retval 70 Internal color state is invalid.
__bashlog_human_color_enabled() {
  case ${__bashlog_color_mode} in
    never) return 1 ;;
    always) return 0 ;;
    auto)
      if [[ -t 2 ]]; then
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
## Arguments are LEVEL, TIMESTAMP, MESSAGE, then zero or more TAG values.  Color,
## when enabled, decorates only the severity token and is reset before tag/message
## text is appended.
## @param level Canonical severity.
## @param timestamp Generated timestamp or empty string.
## @param message Formatted caller message, already redacted when requested.
## @param tags Zero or more caller tags, already redacted when requested.
## @retval 0 The rendered record was written to `__bashlog_render_result`.
## @retval 70 Presentation state is invalid.
__bashlog_render_human() {
  local level=$1
  local timestamp=$2
  local message=$3
  shift 3
  local candidate=
  local level_text=${level}
  local tag
  local color_status

  __bashlog_human_color_enabled
  color_status=$?
  if (( color_status == 70 )); then
    return 70
  fi
  if (( color_status == 0 )); then
    if ! __bashlog_human_color_code "${level}"; then
      return 70
    fi
    level_text=$'\033['"${__bashlog_human_color_code_value}"$'m'"${level}"$'\033[0m'
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
## otherwise they are quoted with the same encoder used for messages.
## @param level Canonical severity.
## @param timestamp Generated timestamp or empty string.
## @param message Formatted caller message, already redacted when requested.
## @param tags Zero or more caller tags, already redacted when requested.
## @retval 0 The rendered record was written to `__bashlog_render_result`.
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
## @brief Selects and executes one renderer for a semantic log record.
## @details
## Arguments are LEVEL, TIMESTAMP, MESSAGE, then zero or more TAG values.  The
## resolved renderer is selected for each logging operation so ordinary stderr
## redirection can change `auto` behavior without changing application source.
## @param level Canonical severity.
## @param timestamp Generated timestamp or empty string.
## @param message Formatted caller message.
## @param tags Zero or more caller tags.
## @retval 0 Rendering completed and `__bashlog_render_result` contains the record.
## @retval 70 Renderer selection or rendering failed.
__bashlog_render_record() {
  if ! __bashlog_format_resolve; then
    return 70
  fi

  case ${__bashlog_resolved_format} in
    human) __bashlog_render_human "$@" ;;
    logfmt) __bashlog_render_logfmt "$@" ;;
    *) return 70 ;;
  esac
}
