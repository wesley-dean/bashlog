# shellcheck shell=bash
## @file lib/level.bash
## @brief Defines the documented public log-level interface for bashlog.
## @details
## This module owns the public threshold-query and threshold-update contracts.
## The active threshold uses the canonical eight-level severity vocabulary
## defined by the public specification, with `info` (`6`) as the initial value.
##
## This file is currently an interface-documentation scaffold.  It is not yet
## assembled into the generated bashlog artifact.  The placeholder function
## bodies exist only so the exact `bash-doxygen` documentation can live beside
## the declarations it will govern before implementation begins.  The bodies
## will be replaced when the contract tests are activated.
##
## The implementation must preserve caller shell state and must not invoke
## external commands.  Invalid threshold changes are atomic: the previous value
## remains active when validation fails.
## @see doc/bashlog-spec.md
## @see doc/adr/ADR-002-bash-runtime-and-portability-baseline.md
## @see doc/adr/ADR-014-pure-bash-runtime-and-external-command-boundary.md
## @see doc/adr/ADR-017-logging-pipeline-levels-formatting-and-emission.md

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
  # Non-runtime documentation scaffold.  Implementation replaces this body.
  return 70
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
  # Non-runtime documentation scaffold.  Implementation replaces this body.
  return 70
}
