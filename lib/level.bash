# shellcheck shell=bash
## @file lib/level.bash
## @brief Implements the public log-level interface for bashlog.
## @details
## This module owns canonical severity validation plus the process-local logging
## threshold.  The active threshold uses the eight-level severity vocabulary
## defined by the public specification, with `info` (`6`) as the initial value.
##
## The implementation uses Bash language facilities and builtins only.  Invalid
## threshold changes are atomic: the previous value remains active when
## validation fails.
## @see doc/bashlog-spec.md
## @see doc/adr/ADR-002-bash-runtime-and-portability-baseline.md
## @see doc/adr/ADR-014-pure-bash-runtime-and-external-command-boundary.md
## @see doc/adr/ADR-017-logging-pipeline-levels-formatting-and-emission.md

declare -g __bashlog_active_level=6
declare -g __bashlog_level_number=

## @fn __bashlog_level_to_number()
## @brief Resolves one canonical severity name or number to its numeric value.
## @details
## Validate exactly one severity token and write the normalized numeric value to
## `__bashlog_level_number`.  Canonical names are case-sensitive and aliases are
## intentionally rejected.
## @param level Canonical severity name or integer from 0 through 7.
## @retval 0 The level was valid and `__bashlog_level_number` was updated.
## @retval 64 The argument count or level value was invalid.
__bashlog_level_to_number() {
  if (( $# != 1 )); then
    return 64
  fi

  case $1 in
    emergency | 0) __bashlog_level_number=0 ;;
    alert | 1) __bashlog_level_number=1 ;;
    critical | 2) __bashlog_level_number=2 ;;
    error | 3) __bashlog_level_number=3 ;;
    warning | 4) __bashlog_level_number=4 ;;
    notice | 5) __bashlog_level_number=5 ;;
    info | 6) __bashlog_level_number=6 ;;
    debug | 7) __bashlog_level_number=7 ;;
    *) return 64 ;;
  esac

  return 0
}

## @fn __bashlog_level_to_name()
## @brief Resolves one numeric severity to its canonical lowercase name.
## @details
## Write the canonical name to `__bashlog_level_name`.  This helper is internal
## and expects a normalized numeric level from 0 through 7.
## @param level Numeric severity from 0 through 7.
## @retval 0 The level was valid and `__bashlog_level_name` was updated.
## @retval 64 The argument count or numeric level was invalid.
declare -g __bashlog_level_name=
__bashlog_level_to_name() {
  if (( $# != 1 )); then
    return 64
  fi

  case $1 in
    0) __bashlog_level_name=emergency ;;
    1) __bashlog_level_name=alert ;;
    2) __bashlog_level_name=critical ;;
    3) __bashlog_level_name=error ;;
    4) __bashlog_level_name=warning ;;
    5) __bashlog_level_name=notice ;;
    6) __bashlog_level_name=info ;;
    7) __bashlog_level_name=debug ;;
    *) return 64 ;;
  esac

  return 0
}

## @fn bashlog_level_get()
## @brief Writes the active canonical bashlog severity threshold.
## @details
## Emit the canonical lowercase name for the currently active threshold.  The
## initial threshold is `info`.  This function accepts no arguments and does not
## mutate logging policy.
##
## This function is intentionally a data-producing API and therefore writes its
## result to standard output rather than the logging sink on standard error.
## @par Standard Output
## The active canonical severity name followed by exactly one newline on
## success.  No level value is written when argument validation fails.
## @par Standard Error
## No routine output.
## @retval 0 The active threshold was written successfully.
## @retval 64 One or more unexpected arguments were supplied.
## @par Examples
## @code
## current_level="$(bashlog_level_get)" || exit
## printf 'active logging threshold: %s\n' "${current_level}"
## @endcode
## @see bashlog_level_set()
bashlog_level_get() {
  if (( $# != 0 )); then
    return 64
  fi

  __bashlog_level_to_name "${__bashlog_active_level}" || return 64
  printf '%s\n' "${__bashlog_level_name}"
}

## @fn bashlog_level_set()
## @brief Changes the active bashlog severity threshold.
## @details
## Accept exactly one canonical severity name or its corresponding integer from
## `0` through `7`.  Canonical names are `emergency`, `alert`, `critical`,
## `error`, `warning`, `notice`, `info`, and `debug`; names are case-sensitive
## and aliases are not accepted by the initial public contract.
##
## A successful call changes the threshold for subsequent logging operations in
## the current Bash process.  Validation is atomic: an invalid value or argument
## count leaves the previous threshold unchanged.
## @param level Canonical severity name or numeric severity from 0 through 7.
## @par Standard Output
## No output.
## @par Standard Error
## No routine output.
## @retval 0 The threshold was changed successfully.
## @retval 64 The level is missing, extra arguments were supplied, or the value
## is not a canonical severity name or integer from 0 through 7.
## @par Examples
## @code
## bashlog_level_set warning || exit
## bashlog_level_set 7 || exit
## @endcode
## @see bashlog_level_get()
bashlog_level_set() {
  local candidate

  if (( $# != 1 )); then
    return 64
  fi

  __bashlog_level_to_number "$1" || return 64
  candidate=${__bashlog_level_number}
  __bashlog_active_level=${candidate}
  return 0
}
