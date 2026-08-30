# shellcheck shell=bash
## @file lib/logging.bash
## @brief Implements the documented public logging interface for bashlog.
## @details
## This module owns the generic logging entry point and the eight canonical
## severity helpers.  Every helper delegates to one common logging pipeline:
## validate the call and requested context, apply threshold policy, construct the
## message with Bash builtin printf semantics, render the canonical severity
## label, apply and verify redaction when requested, and emit the final record to
## standard error.
##
## All routine logging output belongs on standard error.  Standard output remains
## available for application data and for public transformation/query functions.
## A threshold-suppressed logging call is successful and returns zero without
## constructing its message after syntax and requested-context validation have
## succeeded.
## @see doc/bashlog-spec.md
## @see doc/adr/ADR-013-sourceable-library-scope-and-responsibility-boundary.md
## @see doc/adr/ADR-017-logging-pipeline-levels-formatting-and-emission.md
## @see doc/adr/ADR-018-redaction-as-an-opt-in-security-boundary.md
## @see doc/adr/ADR-024-final-redaction-verification-and-fail-closed-output.md

## @fn bashlog_log()
## @brief Logs one message at an explicitly selected canonical severity.
## @details
## Accept a canonical severity name followed by optional `--context CONTEXT`, an
## optional `--` option terminator, a printf-style format string, and zero or
## more format arguments.  Only `--context` and `--` are recognized as logging
## options by the initial public contract.
##
## The requested context, when present, is validated before threshold
## suppression is considered.  A valid call whose severity is below the active
## threshold returns success and emits nothing.  Eligible messages are formatted,
## rendered as `level: message`, redacted and finally verified when a context is
## selected, then emitted to standard error with exactly one trailing newline.
##
## Caller-controlled data should normally be passed as arguments to a literal
## format such as `%s`.  Arbitrary caller data used as the format string receives
## Bash builtin printf semantics.
## @param level Canonical severity name: emergency, alert, critical, error,
## warning, notice, info, or debug.
## @param args Optional `--context CONTEXT`, optional `--`, FORMAT, and printf
## arguments as defined by the public specification.
## @par Standard Output
## No routine output.
## @par Standard Error
## On successful emission, one final verified log record in the form
## `level: message` followed by exactly one newline.  Threshold suppression emits
## nothing.  Fail-closed redaction errors may emit only the fixed safe diagnostic
## `bashlog: message suppressed` when that diagnostic itself can be emitted
## safely.
## @retval 0 The record was emitted successfully or was intentionally suppressed
## by the active threshold.
## @retval 64 Invalid level, arguments, option syntax, context identifier, or
## printf-style formatting input.
## @retval 69 A specifically requested valid context is unknown or destroyed.
## @retval 70 Redaction, final verification, or another security-sensitive
## transformation could not be completed safely.
## @retval 74 Final emission to standard error failed.
## @par Examples
## @code
## bashlog_log info 'application started'
## bashlog_log warning --context auth 'token=%s' "${token}"
## bashlog_log error -- '--message begins with a dash'
## @endcode
## @see bashlog_debug()
## @see bashlog_info()
## @see bashlog_notice()
## @see bashlog_warning()
## @see bashlog_error()
## @see bashlog_critical()
## @see bashlog_alert()
## @see bashlog_emergency()
bashlog_log() {
  local level
  local level_number
  local context_index=-1
  local context_seen=0
  local format
  local message
  local candidate
  local status

  if (( $# < 2 )); then
    return 64
  fi

  level=$1
  shift

  case ${level} in
    emergency | alert | critical | error | warning | notice | info | debug) ;;
    *) return 64 ;;
  esac

  if ! __bashlog_level_to_number "${level}"; then
    return 64
  fi
  level_number=${__bashlog_level_number}

  while (( $# > 0 )); do
    case $1 in
      --context)
        if (( context_seen || $# < 2 )); then
          return 64
        fi
        if __bashlog_context_resolve_active "$2"; then
          status=0
        else
          status=$?
        fi
        if (( status != 0 )); then
          return "${status}"
        fi
        context_index=${__bashlog_context_index}
        context_seen=1
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        return 64
        ;;
      *)
        break
        ;;
    esac
  done

  if (( $# == 0 )); then
    return 64
  fi

  if (( level_number > __bashlog_active_level )); then
    return 0
  fi

  format=$1
  shift

  if printf -v message -- "${format}" "$@" 2>/dev/null; then
    :
  else
    return 64
  fi

  candidate="${level}: ${message}"

  if (( context_seen )); then
    if ! __bashlog_redact_context "${context_index}" "${candidate}"; then
      __bashlog_emit_suppression_diagnostic "${context_index}"
      return 70
    fi
    candidate=${__bashlog_redacted_result}
  fi

  if ! printf '%s\n' "${candidate}" >&2; then
    return 74
  fi

  return 0
}

## @fn bashlog_debug()
## @brief Logs one debug-severity message through the common bashlog pipeline.
## @details Equivalent in logging behavior to `bashlog_log debug ...`.
## @param args Context/option syntax, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction or final verification failed safely.
## @retval 74 Final standard-error emission failed.
bashlog_debug() {
  bashlog_log debug "$@"
}

## @fn bashlog_info()
## @brief Logs one info-severity message through the common bashlog pipeline.
## @details Equivalent in logging behavior to `bashlog_log info ...`.
## @param args Context/option syntax, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction or final verification failed safely.
## @retval 74 Final standard-error emission failed.
bashlog_info() {
  bashlog_log info "$@"
}

## @fn bashlog_notice()
## @brief Logs one notice-severity message through the common bashlog pipeline.
## @details Equivalent in logging behavior to `bashlog_log notice ...`.
## @param args Context/option syntax, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction or final verification failed safely.
## @retval 74 Final standard-error emission failed.
bashlog_notice() {
  bashlog_log notice "$@"
}

## @fn bashlog_warning()
## @brief Logs one warning-severity message through the common bashlog pipeline.
## @details
## Equivalent in logging behavior to `bashlog_log warning ...`.  The canonical
## namespaced spelling is `bashlog_warning`; shorter generic names remain
## application-owned.
## @param args Context/option syntax, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction or final verification failed safely.
## @retval 74 Final standard-error emission failed.
bashlog_warning() {
  bashlog_log warning "$@"
}

## @fn bashlog_error()
## @brief Logs one error-severity message through the common bashlog pipeline.
## @details
## Equivalent in logging behavior to `bashlog_log error ...`.  Logging an error
## does not install traps, exit the caller, or adopt application control-flow
## policy.
## @param args Context/option syntax, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction or final verification failed safely.
## @retval 74 Final standard-error emission failed.
bashlog_error() {
  bashlog_log error "$@"
}

## @fn bashlog_critical()
## @brief Logs one critical-severity message through the common bashlog pipeline.
## @details Equivalent in logging behavior to `bashlog_log critical ...`.
## @param args Context/option syntax, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction or final verification failed safely.
## @retval 74 Final standard-error emission failed.
bashlog_critical() {
  bashlog_log critical "$@"
}

## @fn bashlog_alert()
## @brief Logs one alert-severity message through the common bashlog pipeline.
## @details Equivalent in logging behavior to `bashlog_log alert ...`.
## @param args Context/option syntax, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction or final verification failed safely.
## @retval 74 Final standard-error emission failed.
bashlog_alert() {
  bashlog_log alert "$@"
}

## @fn bashlog_emergency()
## @brief Logs one emergency-severity message through the common bashlog pipeline.
## @details
## Equivalent in logging behavior to `bashlog_log emergency ...`.  This helper
## logs only; it does not terminate the caller or install error handling.
## @param args Context/option syntax, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction or final verification failed safely.
## @retval 74 Final standard-error emission failed.
bashlog_emergency() {
  bashlog_log emergency "$@"
}
