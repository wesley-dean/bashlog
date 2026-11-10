# shellcheck shell=bash
## @file lib/logging.bash
## @brief Implements the documented public logging interface for bashlog.
## @details
## This module owns the generic logging entry point and the eight canonical
## severity helpers.  Every helper delegates to one common pipeline: validate the
## call and any explicitly requested context, apply threshold policy, construct
## the semantic message with Bash builtin printf semantics, optionally redact
## caller-supplied semantic fields, render the record through the selected human
## or logfmt renderer, perform final verification when a context was selected,
## and deliver the completed record immediately or append it to a named queue.
##
## Redaction remains developer-owned and opt-in.  A caller may invoke
## `bashlog_redact` independently before logging, or may pass `--context CONTEXT`
## to delegate redaction of the formatted message and tags to this pipeline.  A
## logging call without `--context` does not inspect registered contexts.
##
## Logging defaults to standard error; explicit --to STDOUT or --to queue:NAME
## is an opt-in redirection.  Queues contain only completed record bytes.
## A threshold-suppressed logging call is successful and returns zero without
## constructing its message or acquiring presentation metadata after syntax and
## requested-context validation have succeeded.
## @see doc/bashlog-spec.md
## @see doc/adr/ADR-013-sourceable-library-scope-and-responsibility-boundary.md
## @see doc/adr/ADR-017-logging-pipeline-levels-formatting-and-emission.md
## @see doc/adr/ADR-018-redaction-as-an-opt-in-security-boundary.md
## @see doc/adr/ADR-024-final-redaction-verification-and-fail-closed-output.md
## @see doc/adr/ADR-025-optional-presentation-metadata-tags-and-color.md
## @see doc/adr/ADR-026-adaptive-human-logfmt-rendering-and-stderr-transport.md
## @see doc/adr/ADR-034-explicit-destinations-and-deferred-logging-queues.md


## @var __bashlog_queue_records
## @brief Named FIFO queues of completed, newline-terminated log records.
## @details Records are rendered and optionally redacted and verified before
## being stored.  Queue clearing is not a promise of secure memory erasure.
declare -gA __bashlog_queue_records=()

## @fn __bashlog_queue_name_valid()
## @brief Checks a nonempty ASCII alphanumeric, case-sensitive queue name.
## @param name Queue name without its queue: prefix.
## @retval 0 Name valid.
## @retval 1 Invalid name or argument count.
__bashlog_queue_name_valid() {
  local LC_ALL=C
  (( $# == 1 )) && [[ $1 =~ ^[A-Za-z0-9]+$ ]]
}

## @fn __bashlog_destination_valid()
## @brief Checks a supported immediate or deferred destination.
## @details The exact grammar is STDERR, STDOUT, or queue:[A-Za-z0-9]+.
## This helper never evaluates or executes destination text.
## @param destination Destination identifier.
## @retval 0 Valid destination.
## @retval 1 Invalid destination.
__bashlog_destination_valid() {
  if (( $# != 1 )); then
    return 1
  fi
  case $1 in
    STDERR | STDOUT) return 0 ;;
    queue:*) __bashlog_queue_name_valid "${1#queue:}" ;;
    *) return 1 ;;
  esac
}

## @fn bashlog_queue_flush()
## @brief Emits one named queue, then clears it only after full write success.
## @details
## NAME is the queue name without queue:.  Optional --to accepts only STDERR
## or STDOUT; the default is STDERR regardless of logging configuration.
## Queued data is replayed byte-for-byte without formatting or reverification.
## A write failure leaves the entire queue intact for a caller-managed retry,
## which may duplicate bytes already observed before a partial failure.
## Nonexistent and empty queues succeed without output.
## @param name Case-sensitive ASCII alphanumeric queue name.
## @param args Optional --to STDERR or --to STDOUT.
## @par Standard Output
## Queued records only when STDOUT is explicitly selected.
## @par Standard Error
## Queued records for omitted or explicit STDERR destination.
## @retval 0 Successful flush or empty/nonexistent queue.
## @retval 64 Invalid argument, queue name, or flush destination.
## @retval 74 Stream emission failed; full queue retained.
bashlog_queue_flush() {
  local name
  local destination=STDERR
  local records

  if (( $# != 1 && $# != 3 )); then
    return 64
  fi
  name=$1
  if ! __bashlog_queue_name_valid "${name}"; then
    return 64
  fi

  if (( $# == 3 )); then
    if [[ $2 != --to ]]; then
      return 64
    fi
    case $3 in
      STDERR | STDOUT) destination=$3 ;;
      *) return 64 ;;
    esac
  fi

  records=${__bashlog_queue_records[$name]-}
  if [[ -z ${records} ]]; then
    return 0
  fi

  case ${destination} in
    STDERR)
      if ! printf '%s' "${records}" >&2; then
        return 74
      fi
      ;;
    STDOUT)
      if ! printf '%s' "${records}" >&1; then
        return 74
      fi
      ;;
  esac

  unset "__bashlog_queue_records[$name]"
  return 0
}

## @fn bashlog_queue_clear()
## @brief Discards one queue without emitting its contents.
## @details No implicit flush, exit trap, context change, or secure erasure
## is promised.  An empty or nonexistent queue is a successful no-op.
## @param name Queue name, without queue: prefix.
## @retval 0 Queue cleared or already empty.
## @retval 64 Invalid name or argument count.
bashlog_queue_clear() {
  if (( $# != 1 )) || ! __bashlog_queue_name_valid "$1"; then
    return 64
  fi
  unset "__bashlog_queue_records[$1]"
  return 0
}

## @fn bashlog_log()
## @brief Logs one message at an explicitly selected canonical severity.
## @details
## Accept a canonical severity name followed by optional repeatable `--tag TAG`,
## optional `--context CONTEXT`, optional `--to DESTINATION`, optional `--`, a printf-
## style format string, and zero or more format arguments.  `--` is required when
## the intended format string begins with `-` or could otherwise be interpreted
## as a bashlog option.
##
## The requested context, when present, and all logging option syntax are
## validated before threshold suppression is considered.  A valid call whose
## severity is below the active threshold returns success and emits nothing.
## Eligible messages are formatted as semantic message data.  When a context was
## explicitly selected, the formatted message and each tag are transformed and
## verified independently before presentation serialization.  Library-generated
## severity and timestamp fields are not transformed by the primary redaction
## pass.  The selected renderer then produces human or logfmt text, after which a
## context-protected call receives final non-transforming verification before
## delivery to a selected stream or queue, including its terminating newline.
##
## A call without `--context` performs no logging-pipeline redaction.  Registered
## contexts are not ambient policy.  Callers that already invoked `bashlog_redact`
## may log that caller-managed result normally without selecting a context again.
##
## Caller-controlled data should normally be passed as arguments to a literal
## format such as `%s`.  Arbitrary caller data used as the format string receives
## Bash builtin printf semantics.
## @param level Canonical severity name: emergency, alert, critical, error,
## warning, notice, info, or debug.
## @param args Optional `--to DESTINATION`, `--context CONTEXT`, repeatable tags, `--`,
## FORMAT, and printf arguments as defined by the public specification.
## @par Standard Output
## One record only when --to STDOUT is selected.
## @par Standard Error
## One record by default or explicit --to STDERR.  Fail-closed context errors
## may emit only the fixed safe diagnostic `bashlog: message suppressed` when that
## diagnostic itself can be emitted safely.
## @retval 0 The record was emitted successfully or was intentionally suppressed
## by the active threshold.
## @retval 64 Invalid level, arguments, option syntax, tag, context identifier, or
## printf-style formatting input.
## @retval 69 A specifically requested valid context is unknown or destroyed.
## @retval 70 Redaction, final verification, timestamp generation, renderer
## selection, or another internal transformation could not be completed safely.
## @retval 74 Final selected-stream emission failed.
## @par Examples
## @code
## bashlog_log info 'application started'
## bashlog_log warning --tag database 'connection delayed'
## bashlog_log warning --context auth 'token=%s' "${token}"
## bashlog_log error --context auth -- '-token=%s' "${token}"
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
  local destination=STDERR
  local destination_seen=0
  local render_fd=2
  local queue_name
  local format
  local message
  local timestamp
  local candidate
  local status
  local tag
  local index
  local tag_count=0
  local -a tags=()

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
      --to)
        if (( destination_seen || $# < 2 )); then
          return 64
        fi
        if ! __bashlog_destination_valid "$2"; then
          return 64
        fi
        destination=$2
        destination_seen=1
        shift 2
        ;;
      --tag)
        if (( $# < 2 )) || ! __bashlog_tag_valid "$2"; then
          return 64
        fi
        tags[tag_count]=$2
        ((tag_count += 1))
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

  # Global/context defaults arrive in task #40; preserve STDERR otherwise.
  if [[ ${destination} == STDOUT ]]; then
    render_fd=1
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

  if ! __bashlog_timestamp_acquire; then
    return 70
  fi
  timestamp=${__bashlog_timestamp_value}

  if (( context_seen )); then
    if ! __bashlog_redact_context "${context_index}" "${message}"; then
      __bashlog_emit_suppression_diagnostic "${context_index}"
      return 70
    fi
    message=${__bashlog_redacted_result}

    for ((index = 0; index < tag_count; index++)); do
      tag=${tags[index]}
      if ! __bashlog_redact_context "${context_index}" "${tag}"; then
        __bashlog_emit_suppression_diagnostic "${context_index}"
        return 70
      fi
      tags[index]=${__bashlog_redacted_result}
    done
  fi

  if (( tag_count > 0 )); then
    if ! __bashlog_render_record \
      "${level}" \
      "${timestamp}" \
      "${message}" \
      "${render_fd}" \
      "${tags[@]}"; then
      if (( context_seen )); then
        __bashlog_emit_suppression_diagnostic "${context_index}"
      fi
      return 70
    fi
  else
    if ! __bashlog_render_record \
      "${level}" \
      "${timestamp}" \
      "${message}" \
      "${render_fd}"; then
      if (( context_seen )); then
        __bashlog_emit_suppression_diagnostic "${context_index}"
      fi
      return 70
    fi
  fi
  candidate=${__bashlog_render_result}

  if (( context_seen )); then
    if ! __bashlog_context_verify "${context_index}" "${candidate}"; then
      __bashlog_emit_suppression_diagnostic "${context_index}"
      return 70
    fi
  fi

  case ${destination} in
    STDERR)
      if ! printf '%s\n' "${candidate}" >&2; then
        return 74
      fi
      ;;
    STDOUT)
      if ! printf '%s\n' "${candidate}" >&1; then
        return 74
      fi
      ;;
    queue:*)
      queue_name=${destination#queue:}
      # Final verification is complete: preserve these exact bytes for flush.
      __bashlog_queue_records["${queue_name}"]+="${candidate}"$'\n'
      ;;
  esac

  return 0
}

## @fn bashlog_debug()
## @brief Logs one debug-severity message through the common bashlog pipeline.
## @details Equivalent in logging behavior to `bashlog_log debug ...`.
## @param args Destination/context/tag options, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, tag, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction, verification, timestamp, or rendering failed safely.
## @retval 74 Final selected-stream emission failed.
bashlog_debug() {
  bashlog_log debug "$@"
}

## @fn bashlog_info()
## @brief Logs one info-severity message through the common bashlog pipeline.
## @details Equivalent in logging behavior to `bashlog_log info ...`.
## @param args Destination/context/tag options, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, tag, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction, verification, timestamp, or rendering failed safely.
## @retval 74 Final selected-stream emission failed.
bashlog_info() {
  bashlog_log info "$@"
}

## @fn bashlog_notice()
## @brief Logs one notice-severity message through the common bashlog pipeline.
## @details Equivalent in logging behavior to `bashlog_log notice ...`.
## @param args Destination/context/tag options, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, tag, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction, verification, timestamp, or rendering failed safely.
## @retval 74 Final selected-stream emission failed.
bashlog_notice() {
  bashlog_log notice "$@"
}

## @fn bashlog_warning()
## @brief Logs one warning-severity message through the common bashlog pipeline.
## @details
## Equivalent in logging behavior to `bashlog_log warning ...`.  The canonical
## namespaced spelling is `bashlog_warning`; shorter generic names remain
## application-owned.
## @param args Destination/context/tag options, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, tag, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction, verification, timestamp, or rendering failed safely.
## @retval 74 Final selected-stream emission failed.
bashlog_warning() {
  bashlog_log warning "$@"
}

## @fn bashlog_error()
## @brief Logs one error-severity message through the common bashlog pipeline.
## @details
## Equivalent in logging behavior to `bashlog_log error ...`.  Logging an error
## does not install traps, exit the caller, or adopt application control-flow
## policy.
## @param args Destination/context/tag options, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, tag, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction, verification, timestamp, or rendering failed safely.
## @retval 74 Final selected-stream emission failed.
bashlog_error() {
  bashlog_log error "$@"
}

## @fn bashlog_critical()
## @brief Logs one critical-severity message through the common bashlog pipeline.
## @details Equivalent in logging behavior to `bashlog_log critical ...`.
## @param args Destination/context/tag options, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, tag, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction, verification, timestamp, or rendering failed safely.
## @retval 74 Final selected-stream emission failed.
bashlog_critical() {
  bashlog_log critical "$@"
}

## @fn bashlog_alert()
## @brief Logs one alert-severity message through the common bashlog pipeline.
## @details Equivalent in logging behavior to `bashlog_log alert ...`.
## @param args Destination/context/tag options, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, tag, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction, verification, timestamp, or rendering failed safely.
## @retval 74 Final selected-stream emission failed.
bashlog_alert() {
  bashlog_log alert "$@"
}

## @fn bashlog_emergency()
## @brief Logs one emergency-severity message through the common bashlog pipeline.
## @details
## Equivalent in logging behavior to `bashlog_log emergency ...`.  This helper
## logs only; it does not terminate the caller or install error handling.
## @param args Destination/context/tag options, FORMAT, and printf arguments accepted by bashlog_log().
## @retval 0 Emitted successfully or intentionally threshold-suppressed.
## @retval 64 Invalid arguments, option syntax, tag, context identifier, or formatting.
## @retval 69 Requested context unknown or destroyed.
## @retval 70 Redaction, verification, timestamp, or rendering failed safely.
## @retval 74 Final selected-stream emission failed.
bashlog_emergency() {
  bashlog_log emergency "$@"
}
