# shellcheck shell=bash
## @file lib/redaction.bash
## @brief Implements the documented public redaction interface for bashlog.
## @details
## This module owns redaction-rule registration, redaction-context destruction,
## and the transform-only redaction API.  The internal matcher and verification
## engine lives in `lib/redaction-core.bash`; this module provides the stable
## namespaced public boundary around that state.
##
## Redaction state is append-only while a context is active.  Replacement text
## is always literal.  The implementation fails closed when transformation or
## final verification cannot establish that output satisfies the selected
## policy.  Context destruction releases bashlog-owned active references but is
## not secure memory erasure.
## @see doc/bashlog-spec.md
## @see doc/adr/ADR-018-redaction-as-an-opt-in-security-boundary.md
## @see doc/adr/ADR-020-redaction-context-lifecycle-and-state-model.md
## @see doc/adr/ADR-021-redaction-rule-registration-ordering-and-replacement.md
## @see doc/adr/ADR-022-fixed-string-redaction-and-multibyte-guarantees.md
## @see doc/adr/ADR-023-glob-and-ere-redaction-semantics.md
## @see doc/adr/ADR-024-final-redaction-verification-and-fail-closed-output.md

## @fn bashlog_redaction_add()
## @brief Appends one validated redaction rule to a named context.
## @details
## Accept exactly four arguments: context identifier, matcher name, pattern, and
## literal replacement.  Supported matcher names are exactly `fixed`, `glob`,
## and `ere` and are case-sensitive.
##
## The first successful rule registration for an unseen context creates the
## context atomically.  A failed registration leaves an unseen context unseen and
## leaves an active context unchanged.  Active contexts are append-only and
## preserve exact successful registration order.
##
## Empty patterns are invalid.  Empty replacement text is valid and removes each
## match.  Duplicate `(matcher, pattern)` pairs within one context are rejected.
## A rule whose replacement itself satisfies the same matcher is rejected as
## predictably unsatisfiable.  Glob/ERE patterns capable of matching empty input,
## invalid EREs, and unsupported extglob syntax are also rejected.
##
## Replacement text is opaque literal data.  Characters such as `&`, `\1`,
## `$()`, `${NAME}`, `*`, `?`, `[`, and `]` never acquire replacement-language or
## shell-evaluation semantics.
## @param context Non-empty ASCII context identifier matching
## `[A-Za-z_][A-Za-z0-9_.:-]*`.
## @param matcher Exact matcher name: fixed, glob, or ere.
## @param pattern Non-empty matcher pattern governed by the selected matcher.
## @param replacement Literal replacement text; may be empty.
## @par Standard Output
## No output.
## @par Standard Error
## No success output.  Failure diagnostics do not reproduce the supplied pattern
## or replacement.
## @retval 0 The rule was appended successfully and an unseen context, if any,
## became active atomically.
## @retval 64 Invalid argument count, invalid context identifier, or unknown
## matcher name.
## @retval 65 Invalid, duplicate, zero-length-capable, self-matching, or otherwise
## unsatisfiable rule.
## @retval 69 The context name is a destroyed context tombstone and cannot be
## reused during the current Bash process.
## @par Examples
## @code
## bashlog_redaction_add auth fixed "${password}" '[REDACTED PASSWORD]' || exit
## bashlog_redaction_add request ere '[0-9]{3}-[0-9]{2}-[0-9]{4}' '[REDACTED SSN]' || exit
## @endcode
## @see bashlog_redact()
## @see bashlog_redaction_context_destroy()
bashlog_redaction_add() {
  local context
  local matcher
  local pattern
  local replacement
  local context_index=-1
  local index
  local validation_status

  if (( $# != 4 )); then
    return 64
  fi

  context=$1
  matcher=$2
  pattern=$3
  replacement=$4

  if ! __bashlog_context_name_valid "${context}"; then
    return 64
  fi

  case ${matcher} in
    fixed | glob | ere) ;;
    *) return 64 ;;
  esac

  if __bashlog_context_find "${context}"; then
    context_index=${__bashlog_context_index}
    if [ "${__bashlog_context_states[context_index]}" != active ]; then
      return 69
    fi
  fi

  if __bashlog_rule_validate "${matcher}" "${pattern}" "${replacement}"; then
    validation_status=0
  else
    validation_status=$?
  fi
  if (( validation_status != 0 )); then
    return "${validation_status}"
  fi

  if (( context_index >= 0 )); then
    for ((index = 0; index < __bashlog_rule_count; index++)); do
      if (( __bashlog_rule_contexts[index] != context_index )); then
        continue
      fi
      if [ "${__bashlog_rule_matchers[index]}" = "${matcher}" ] && \
        [ "${__bashlog_rule_patterns[index]}" = "${pattern}" ]; then
        return 65
      fi
    done
  else
    context_index=${__bashlog_context_count}
    __bashlog_context_names[context_index]=${context}
    __bashlog_context_states[context_index]=active
    __bashlog_context_count=$((__bashlog_context_count + 1))
  fi

  index=${__bashlog_rule_count}
  __bashlog_rule_contexts[index]=${context_index}
  __bashlog_rule_matchers[index]=${matcher}
  __bashlog_rule_patterns[index]=${pattern}
  __bashlog_rule_replacements[index]=${replacement}
  __bashlog_rule_count=$((__bashlog_rule_count + 1))

  return 0
}

## @fn bashlog_redaction_context_destroy()
## @brief Destroys one active redaction context as a bashlog policy object.
## @details
## Make the complete named context unavailable for future logging, redaction,
## and rule registration.  Destruction applies to the whole context; the public
## API does not delete or mutate individual rules.
##
## On success, bashlog removes its active references to the context rule data as
## far as the implementation can intentionally control and retains only
## non-secret tombstone state needed to prevent reuse of that context name in the
## current Bash process.
##
## This operation is explicitly not secure erasure, zeroization, memory wiping,
## or cryptographic destruction.  Bash may retain historical copies of values in
## memory beyond the references controlled by bashlog.
## @param context Active context identifier matching
## `[A-Za-z_][A-Za-z0-9_.:-]*`.
## @par Standard Output
## No output.
## @par Standard Error
## No routine output on success.  Failure diagnostics do not reveal
## secret-bearing context rule contents.
## @retval 0 The active context was destroyed as a bashlog policy object.
## @retval 64 Invalid argument count or invalid context identifier.
## @retval 69 The context is unknown or was already destroyed.
## @par Examples
## @code
## bashlog_redaction_context_destroy auth || exit
## @endcode
## @warning Successful destruction does not prove that prior secret bytes no
## longer exist anywhere in process or operating-system memory.
## @see bashlog_redaction_add()
## @see bashlog_redact()
bashlog_redaction_context_destroy() {
  local context_index
  local index
  local status

  if (( $# != 1 )); then
    return 64
  fi

  if __bashlog_context_resolve_active "$1"; then
    status=0
  else
    status=$?
  fi
  if (( status != 0 )); then
    return "${status}"
  fi

  context_index=${__bashlog_context_index}
  __bashlog_context_states[context_index]=destroyed

  for ((index = 0; index < __bashlog_rule_count; index++)); do
    if (( __bashlog_rule_contexts[index] != context_index )); then
      continue
    fi

    __bashlog_rule_contexts[index]=-1
    __bashlog_rule_matchers[index]=
    __bashlog_rule_patterns[index]=
    __bashlog_rule_replacements[index]=
  done

  return 0
}

## @fn bashlog_redact()
## @brief Redacts and finally verifies one string under an active context.
## @details
## Transform exactly one Bash string using every active rule in the named context
## in successful registration order.  Each rule receives one bounded global,
## non-overlapping pass.  Replacement text inserted by a rule is not recursively
## rescanned by that same rule, and the complete rule set is not restarted until
## a fixed point is reached.
##
## After the ordered transformation pass, recheck the complete candidate against
## every active fixed, glob, and ERE rule.  The value is returned only when none
## of the active rules matches at that final boundary.  A remaining match,
## matcher-evaluation error, or inability to establish policy compliance fails
## closed; the original input is never returned as a fallback.
##
## On success the transformed value is written to standard output with no
## automatically added newline.  This makes the function suitable for command
## substitution and caller-owned sink composition.  The returned value is safe
## only with respect to the selected context at the instant of final verification;
## later caller transformations are outside this guarantee.
## @param context Active context identifier matching
## `[A-Za-z_][A-Za-z0-9_.:-]*`.
## @param string Bash string to transform and verify.
## @par Standard Output
## The successfully redacted and finally verified value with no automatically
## added newline.  On any failure, the original input is not written here.
## @par Standard Error
## No routine success output.  A failure may emit only the fixed safe diagnostic
## `bashlog: message suppressed` when the diagnostic itself can be emitted safely.
## @retval 0 The transformed value passed final verification and was written to
## standard output.
## @retval 64 Invalid argument count or invalid context identifier.
## @retval 69 The requested context is unknown or destroyed.
## @retval 70 Transformation or final verification could not be completed safely.
## @par Examples
## @code
## safe_value="$(bashlog_redact auth "${candidate}")" || exit
## printf '%s\n' "${safe_value}"
## @endcode
## @warning Caller-side `set -x` may reveal the original arguments before this
## function receives control.  bashlog cannot undo disclosure at that boundary.
## @see bashlog_redaction_add()
## @see bashlog_redaction_context_destroy()
bashlog_redact() {
  local context_index
  local status

  if (( $# != 2 )); then
    return 64
  fi

  if __bashlog_context_resolve_active "$1"; then
    status=0
  else
    status=$?
  fi
  if (( status != 0 )); then
    return "${status}"
  fi
  context_index=${__bashlog_context_index}

  if ! __bashlog_redact_context "${context_index}" "$2"; then
    __bashlog_emit_suppression_diagnostic "${context_index}"
    return 70
  fi

  if ! printf '%s' "${__bashlog_redacted_result}"; then
    return 70
  fi

  return 0
}
