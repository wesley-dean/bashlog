# shellcheck shell=bash
## @file lib/redaction-core.bash
## @brief Implements bashlog's internal redaction state, matchers, and verifier.
## @details
## This module is the security-critical implementation behind the public
## redaction API.  It stores named context state and ordered rules, performs one
## bounded transformation pass per rule, and verifies the completed candidate
## against every active rule before a caller may emit or return it.
##
## The implementation intentionally uses plainly named parallel indexed arrays
## and explicit loops.  Bash does not provide private memory; the `__bashlog_`
## prefix communicates implementation scope only.  Fixed patterns and
## replacements are retained as plaintext Bash strings while active because exact
## literal redaction requires the original information.
##
## Glob and ERE matching use Bash's native matchers.  The Bash `nocasematch`
## option changes those native operations, while bashlog's accepted contract is
## case-sensitive.  Matching helpers therefore snapshot `nocasematch`, disable it
## only for the individual match operation, and restore the exact enabled/disabled
## state before returning.  No other `shopt` option is changed.
## @see doc/bashlog-spec.md
## @see doc/adr/ADR-018-redaction-as-an-opt-in-security-boundary.md
## @see doc/adr/ADR-019-readability-auditability-and-rejection-of-obscurity.md
## @see doc/adr/ADR-020-redaction-context-lifecycle-and-state-model.md
## @see doc/adr/ADR-021-redaction-rule-registration-ordering-and-replacement.md
## @see doc/adr/ADR-022-fixed-string-redaction-and-multibyte-guarantees.md
## @see doc/adr/ADR-023-glob-and-ere-redaction-semantics.md
## @see doc/adr/ADR-024-final-redaction-verification-and-fail-closed-output.md

## @var __bashlog_context_names
## @brief Ordered context-name table; destroyed names remain as non-secret tombstones.
declare -ga __bashlog_context_names=()

## @var __bashlog_context_states
## @brief Lifecycle state parallel to `__bashlog_context_names`.
declare -ga __bashlog_context_states=()

## @var __bashlog_context_count
## @brief Number of context slots created during the current Bash process.
declare -g __bashlog_context_count=0

## @var __bashlog_context_index
## @brief Internal output slot used by context lookup and resolution helpers.
declare -g __bashlog_context_index=-1

## @var __bashlog_rule_contexts
## @brief Context indexes for globally registration-ordered redaction rules.
declare -ga __bashlog_rule_contexts=()

## @var __bashlog_rule_matchers
## @brief Matcher names parallel to the ordered rule table.
declare -ga __bashlog_rule_matchers=()

## @var __bashlog_rule_patterns
## @brief Secret-bearing matcher patterns parallel to the ordered rule table.
declare -ga __bashlog_rule_patterns=()

## @var __bashlog_rule_replacements
## @brief Literal replacements parallel to the ordered rule table.
declare -ga __bashlog_rule_replacements=()

## @var __bashlog_rule_count
## @brief Number of rule slots allocated during the current Bash process.
declare -g __bashlog_rule_count=0

## @var __bashlog_match_start
## @brief Internal output slot containing a selected match start character offset.
declare -g __bashlog_match_start=-1

## @var __bashlog_match_length
## @brief Internal output slot containing a selected consuming match length.
declare -g __bashlog_match_length=0

## @var __bashlog_transform_result
## @brief Internal output slot containing the most recent transformation result.
declare -g __bashlog_transform_result=

## @var __bashlog_redacted_result
## @brief Internal output slot containing a candidate that passed final verification.
declare -g __bashlog_redacted_result=

## @fn __bashlog_context_name_valid()
## @brief Validates one public redaction context identifier.
## @details
## Context names are deliberately restricted to the ASCII identifier grammar
## `[A-Za-z_][A-Za-z0-9_.:-]*` so they remain identifiers rather than arbitrary
## shell text.
##
## Bash ERE range expressions are locale-sensitive.  A bare `[A-Za-z]` check in
## the caller's locale can therefore admit characters outside ASCII in locales
## whose collation sequence places additional characters inside those ranges.
## Context identifiers are not glob/ERE payloads and do not inherit the pattern
## matchers' caller-locale contract.  This validator uses a function-local C
## locale so the documented ASCII grammar has the same meaning in every caller
## locale without changing locale state after the function returns.
## @param context Proposed context identifier.
## @retval 0 The context identifier is valid.
## @retval 1 The context identifier is invalid.
__bashlog_context_name_valid() {
  local LC_ALL=C

  if (( $# != 1 )); then
    return 1
  fi

  [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_.:-]*$ ]]
}

## @fn __bashlog_context_find()
## @brief Finds a context by name without applying lifecycle policy.
## @details
## Search the small process-local context table and write the matching index to
## `__bashlog_context_index`.  Both active and destroyed contexts are returned so
## callers can distinguish an unseen name from a tombstone.
## @param context Valid or invalid context text to search literally.
## @retval 0 A context with the supplied name exists.
## @retval 1 The name has never been created.
__bashlog_context_find() {
  local context=${1-}
  local index

  __bashlog_context_index=-1
  for ((index = 0; index < __bashlog_context_count; index++)); do
    if [ "${__bashlog_context_names[index]}" = "${context}" ]; then
      __bashlog_context_index=${index}
      return 0
    fi
  done

  return 1
}

## @fn __bashlog_context_resolve_active()
## @brief Resolves one public context name to an active context index.
## @details
## Validate the public identifier grammar, distinguish unseen/destroyed names,
## and expose the active context index through `__bashlog_context_index`.
## @param context Context identifier supplied by a public operation.
## @retval 0 The context exists and is active.
## @retval 64 The context identifier is syntactically invalid.
## @retval 69 The context is unseen or destroyed.
__bashlog_context_resolve_active() {
  if (( $# != 1 )) || ! __bashlog_context_name_valid "$1"; then
    return 64
  fi

  if ! __bashlog_context_find "$1"; then
    return 69
  fi

  if [ "${__bashlog_context_states[__bashlog_context_index]}" != active ]; then
    return 69
  fi

  return 0
}

## @fn __bashlog_glob_whole_match()
## @brief Performs one case-sensitive whole-string Bash glob match.
## @details
## Bash's `nocasematch` option changes `[[ string == pattern ]]`.  Preserve its
## caller-visible state while forcing the individual comparison to remain
## case-sensitive as required by the bashlog matcher contract.
## @param string Candidate string.
## @param pattern Basic Bash glob pattern.
## @retval 0 The complete string matches the pattern.
## @retval 1 The complete string does not match the pattern.
__bashlog_glob_whole_match() {
  local restore_nocasematch=0
  local status

  if shopt -q nocasematch; then
    restore_nocasematch=1
    shopt -u nocasematch
  fi

  [[ $1 == $2 ]]
  status=$?

  if (( restore_nocasematch )); then
    shopt -s nocasematch
  fi

  return "${status}"
}

## @fn __bashlog_ere_match()
## @brief Performs one case-sensitive Bash ERE search and preserves BASH_REMATCH.
## @details
## Match with Bash `[[ string =~ ere ]]` semantics while insulating the result
## from the caller's `nocasematch` setting.  `BASH_REMATCH` intentionally remains
## global because Bash itself defines it that way; callers of this internal helper
## may inspect it immediately after a successful match.
## @param string Candidate string.
## @param pattern Bash extended regular expression supplied as data.
## @retval 0 The expression matched.
## @retval 1 The expression was valid and did not match.
## @retval 2 Bash reported an invalid extended regular expression.
__bashlog_ere_match() {
  local restore_nocasematch=0
  local status

  if shopt -q nocasematch; then
    restore_nocasematch=1
    shopt -u nocasematch
  fi

  [[ $1 =~ $2 ]]
  status=$?

  if (( restore_nocasematch )); then
    shopt -s nocasematch
  fi

  return "${status}"
}

## @fn __bashlog_fixed_find_next()
## @brief Finds the next exact fixed-string occurrence at or after a cursor.
## @details
## Scan Bash character offsets explicitly and compare each same-length slice with
## the Bash `test` builtin.  This avoids glob/ERE interpretation and keeps exact
## fixed matching independent of `nocasematch`.
## @param input Complete rule input.
## @param pattern Non-empty literal fixed pattern.
## @param cursor First character offset eligible for matching.
## @retval 0 A match was found; start and length globals were updated.
## @retval 1 No match exists at or after the cursor.
## @retval 2 The helper received an invalid empty pattern.
__bashlog_fixed_find_next() {
  local input=$1
  local pattern=$2
  local cursor=$3
  local input_length=${#input}
  local pattern_length=${#pattern}
  local start
  local slice

  __bashlog_match_start=-1
  __bashlog_match_length=0

  if (( pattern_length == 0 )); then
    return 2
  fi

  for ((start = cursor; start + pattern_length <= input_length; start++)); do
    slice=${input:start:pattern_length}
    if [ "${slice}" = "${pattern}" ]; then
      __bashlog_match_start=${start}
      __bashlog_match_length=${pattern_length}
      return 0
    fi
  done

  return 1
}

## @fn __bashlog_glob_find_next()
## @brief Finds the next basic-glob substring using leftmost/longest selection.
## @details
## Scan possible start positions from left to right.  At each position, test
## candidate lengths from longest to shortest, which implements the accepted
## leftmost position and longest match at that position without pathname
## expansion or external commands.
## @param input Complete rule input.
## @param pattern Valid non-empty basic Bash glob pattern.
## @param cursor First character offset eligible for matching.
## @retval 0 A consuming match was found; start and length globals were updated.
## @retval 1 No consuming match exists at or after the cursor.
__bashlog_glob_find_next() {
  local input=$1
  local pattern=$2
  local cursor=$3
  local input_length=${#input}
  local start
  local length
  local slice

  __bashlog_match_start=-1
  __bashlog_match_length=0

  for ((start = cursor; start < input_length; start++)); do
    for ((length = input_length - start; length > 0; length--)); do
      slice=${input:start:length}
      if __bashlog_glob_whole_match "${slice}" "${pattern}"; then
        __bashlog_match_start=${start}
        __bashlog_match_length=${length}
        return 0
      fi
    done
  done

  return 1
}

## @fn __bashlog_ere_find_next()
## @brief Locates the next Bash ERE match while preserving whole-input anchors.
## @details
## `BASH_REMATCH` exposes matched text but not portable match offsets.  Searching
## the first literal copy of `BASH_REMATCH[0]` is incorrect for anchored patterns
## such as `foo$` when identical text appears earlier.  Instead, this helper scans
## candidate start offsets and forces the ERE to begin after exactly that many
## characters in the original rule input.  The first successful start therefore
## preserves Bash's whole-input `^` and `$` semantics.  POSIX leftmost/longest
## behavior supplies the longest match at that forced start.
## @param input Complete original input for the current rule pass.
## @param pattern Valid ERE that cannot match empty input.
## @param cursor First character offset eligible for matching.
## @retval 0 A consuming match was found; start and length globals were updated.
## @retval 1 No match exists at or after the cursor.
## @retval 2 Bash reported an unexpected ERE evaluation error.
__bashlog_ere_find_next() {
  local input=$1
  local pattern=$2
  local cursor=$3
  local input_length=${#input}
  local start
  local forced_pattern
  local status
  local matched

  __bashlog_match_start=-1
  __bashlog_match_length=0

  for ((start = cursor; start < input_length; start++)); do
    forced_pattern="^.{${start}}(${pattern})"
    __bashlog_ere_match "${input}" "${forced_pattern}"
    status=$?

    if (( status == 2 )); then
      return 2
    fi

    if (( status == 0 )); then
      matched=${BASH_REMATCH[1]-}
      if (( ${#matched} == 0 )); then
        return 2
      fi
      __bashlog_match_start=${start}
      __bashlog_match_length=${#matched}
      return 0
    fi
  done

  return 1
}

## @fn __bashlog_rule_matches()
## @brief Determines whether one rule matches anywhere in a candidate string.
## @details
## Use the same matcher semantics employed by transformation and final
## verification.  The function performs no replacement and exposes no matched
## content through a public interface.
## @param matcher Matcher name: fixed, glob, or ere.
## @param pattern Matcher pattern.
## @param candidate Candidate text to inspect.
## @retval 0 The rule matches the candidate.
## @retval 1 The rule does not match the candidate.
## @retval 2 Matcher evaluation failed or the matcher name is invalid.
__bashlog_rule_matches() {
  local matcher=$1
  local pattern=$2
  local candidate=$3

  case ${matcher} in
    fixed)
      __bashlog_fixed_find_next "${candidate}" "${pattern}" 0
      return $?
      ;;
    glob)
      __bashlog_glob_find_next "${candidate}" "${pattern}" 0
      return $?
      ;;
    ere)
      __bashlog_ere_match "${candidate}" "${pattern}"
      return $?
      ;;
    *)
      return 2
      ;;
  esac
}

## @fn __bashlog_glob_has_extglob_operator()
## @brief Detects unsupported extended-glob operator syntax literally.
## @details
## Search the proposed glob text for the five extglob operator introducers.  The
## check is deliberately literal so ambient `extglob` state cannot affect
## validation.
## @param pattern Proposed glob pattern.
## @retval 0 Unsupported extglob operator syntax is present.
## @retval 1 No extglob operator introducer is present.
__bashlog_glob_has_extglob_operator() {
  local pattern=$1
  local operator

  for operator in '?(' '*(' '+(' '@(' '!('; do
    if __bashlog_fixed_find_next "${pattern}" "${operator}" 0; then
      return 0
    fi
  done

  return 1
}

## @fn __bashlog_rule_validate()
## @brief Validates one proposed matcher, pattern, and literal replacement.
## @details
## Reject empty patterns, unsupported matcher names, extglob operator syntax,
## invalid EREs, patterns capable of matching empty input, and replacements that
## themselves satisfy the proposed rule.  Validation does not mutate context or
## rule state.
## @param matcher Proposed matcher name.
## @param pattern Proposed pattern.
## @param replacement Proposed literal replacement; may be empty.
## @retval 0 The proposed rule is structurally valid.
## @retval 64 The matcher name is not supported.
## @retval 65 The proposed rule violates a rule-level constraint.
__bashlog_rule_validate() {
  local matcher=$1
  local pattern=$2
  local replacement=$3
  local status

  if [ -z "${pattern}" ]; then
    return 65
  fi

  case ${matcher} in
    fixed)
      ;;
    glob)
      if __bashlog_glob_has_extglob_operator "${pattern}"; then
        return 65
      fi
      if __bashlog_glob_whole_match '' "${pattern}"; then
        return 65
      fi
      ;;
    ere)
      __bashlog_ere_match '' "${pattern}"
      status=$?
      if (( status == 0 || status == 2 )); then
        return 65
      fi
      ;;
    *)
      return 64
      ;;
  esac

  __bashlog_rule_matches "${matcher}" "${pattern}" "${replacement}"
  status=$?
  if (( status == 0 || status == 2 )); then
    return 65
  fi

  return 0
}

## @fn __bashlog_rule_apply()
## @brief Applies one rule in one bounded global non-overlapping pass.
## @details
## Match only against the rule's original input for this pass.  Replacement text
## is concatenated literally into the result and is never rescanned by the same
## rule.  The completed value is written to `__bashlog_transform_result`.
## @param matcher Matcher name.
## @param pattern Accepted matcher pattern.
## @param replacement Literal replacement text.
## @param input Current candidate entering this rule.
## @retval 0 Transformation completed successfully.
## @retval 70 Matcher evaluation failed unexpectedly.
__bashlog_rule_apply() {
  local matcher=$1
  local pattern=$2
  local replacement=$3
  local input=$4
  local input_length=${#input}
  local cursor=0
  local prefix_length
  local status
  local result=

  while (( cursor < input_length )); do
    case ${matcher} in
      fixed) __bashlog_fixed_find_next "${input}" "${pattern}" "${cursor}" ;;
      glob) __bashlog_glob_find_next "${input}" "${pattern}" "${cursor}" ;;
      ere) __bashlog_ere_find_next "${input}" "${pattern}" "${cursor}" ;;
      *) return 70 ;;
    esac
    status=$?

    if (( status == 1 )); then
      break
    fi
    if (( status != 0 || __bashlog_match_length <= 0 )); then
      return 70
    fi

    prefix_length=$((__bashlog_match_start - cursor))
    result="${result}${input:cursor:prefix_length}${replacement}"
    cursor=$((__bashlog_match_start + __bashlog_match_length))
  done

  result="${result}${input:cursor}"
  __bashlog_transform_result=${result}
  return 0
}

## @fn __bashlog_context_transform()
## @brief Applies every active rule for one context in registration order.
## @details
## Rules are stored globally in successful registration order.  Each rule
## receives the candidate produced by the prior rule and performs exactly one
## bounded pass.  The function does not perform final verification.
## @param context_index Active context table index.
## @param input Complete candidate entering redaction.
## @retval 0 All ordered rule transformations completed.
## @retval 70 A rule could not be evaluated safely.
__bashlog_context_transform() {
  local context_index=$1
  local candidate=$2
  local index

  for ((index = 0; index < __bashlog_rule_count; index++)); do
    if (( __bashlog_rule_contexts[index] != context_index )); then
      continue
    fi

    if ! __bashlog_rule_apply \
      "${__bashlog_rule_matchers[index]}" \
      "${__bashlog_rule_patterns[index]}" \
      "${__bashlog_rule_replacements[index]}" \
      "${candidate}"; then
      return 70
    fi
    candidate=${__bashlog_transform_result}
  done

  __bashlog_transform_result=${candidate}
  return 0
}

## @fn __bashlog_context_verify()
## @brief Verifies that a candidate matches none of one context's active rules.
## @details
## This is a non-transforming final boundary.  Any remaining fixed, glob, or ERE
## match, or any matcher-evaluation error, rejects the candidate.
## @param context_index Active context table index.
## @param candidate Candidate text to verify.
## @retval 0 No active rule matches the candidate.
## @retval 70 At least one active rule matches or could not be evaluated safely.
__bashlog_context_verify() {
  local context_index=$1
  local candidate=$2
  local index
  local status

  for ((index = 0; index < __bashlog_rule_count; index++)); do
    if (( __bashlog_rule_contexts[index] != context_index )); then
      continue
    fi

    __bashlog_rule_matches \
      "${__bashlog_rule_matchers[index]}" \
      "${__bashlog_rule_patterns[index]}" \
      "${candidate}"
    status=$?

    if (( status == 0 || status == 2 )); then
      return 70
    fi
  done

  return 0
}

## @fn __bashlog_redact_context()
## @brief Transforms and finally verifies one candidate under an active context.
## @details
## Perform exactly one ordered transformation pass followed by the independent
## non-transforming verification pass.  On success, write the verified value to
## `__bashlog_redacted_result`.  On failure, never replace that result with the
## original input as a fallback.
## @param context_index Active context table index.
## @param input Candidate to transform and verify.
## @retval 0 The redacted candidate passed final verification.
## @retval 70 Transformation or verification failed closed.
__bashlog_redact_context() {
  local context_index=$1
  local input=$2
  local candidate

  __bashlog_redacted_result=

  if ! __bashlog_context_transform "${context_index}" "${input}"; then
    return 70
  fi
  candidate=${__bashlog_transform_result}

  if ! __bashlog_context_verify "${context_index}" "${candidate}"; then
    return 70
  fi

  __bashlog_redacted_result=${candidate}
  return 0
}

## @fn __bashlog_emit_suppression_diagnostic()
## @brief Emits the fixed failure diagnostic only when active policy permits it.
## @details
## The diagnostic is library-owned constant text and contains no failed candidate
## or rule content.  Verify it without transformation against the active context;
## if any rule matches or matcher evaluation fails, remain silent.  Diagnostic
## write failure is intentionally ignored because the original operation already
## has a security-failure status to return.
## @param context_index Active context table index.
## @retval 0 Diagnostic processing completed, whether emitted or suppressed.
__bashlog_emit_suppression_diagnostic() {
  local context_index=$1
  local diagnostic='bashlog: message suppressed'

  if __bashlog_context_verify "${context_index}" "${diagnostic}"; then
    printf '%s\n' "${diagnostic}" >&2 || :
  fi

  return 0
}
