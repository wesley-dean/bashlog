#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  : "${BASHLOG_ARTIFACT:?BASHLOG_ARTIFACT must identify the artifact under test}"
}

run_bashlog_script() {
  run --separate-stderr bash --noprofile --norc -s -- "${BASHLOG_ARTIFACT}" "$@"
}

@test "sourcing bashlog is silent on stdout and stderr" {
  run_bashlog_script <<'BASH'
    source "$1"
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "sourcing bashlog preserves existing traps" {
  run_bashlog_script <<'BASH'
    trap "printf trap-fired >/dev/null" USR1
    before="$(trap -p)"
    source "$1"
    after="$(trap -p)"
    [[ ${before} == "${after}" ]]
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "sourcing bashlog preserves set shell options" {
  run_bashlog_script <<'BASH'
    set +e
    set -u
    set +o pipefail
    before="$(set +o)"
    source "$1"
    after="$(set +o)"
    [[ ${before} == "${after}" ]]
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "sourcing bashlog preserves shopt options" {
  run_bashlog_script <<'BASH'
    shopt -u extglob nullglob expand_aliases
    before="$(shopt -p)"
    source "$1"
    after="$(shopt -p)"
    [[ ${before} == "${after}" ]]
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "sourcing bashlog does not replace caller generic functions" {
  run_bashlog_script <<'BASH'
    info() { printf "%s\n" caller-info; }
    warn() { printf "%s\n" caller-warn; }
    error() { printf "%s\n" caller-error; }
    die() { printf "%s\n" caller-die; }
    before_info="$(declare -f info)"
    before_warn="$(declare -f warn)"
    before_error="$(declare -f error)"
    before_die="$(declare -f die)"
    source "$1"
    [[ $(declare -f info) == "${before_info}" ]]
    [[ $(declare -f warn) == "${before_warn}" ]]
    [[ $(declare -f error) == "${before_error}" ]]
    [[ $(declare -f die) == "${before_die}" ]]
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "sourcing bashlog does not define generic convenience functions" {
  run_bashlog_script <<'BASH'
    source "$1"
    for name in debug info warn warning error critical alert emergency die; do
      if declare -F "${name}" >/dev/null; then
        printf "unexpected generic function: %s\n" "${name}" >&2
        exit 1
      fi
    done
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "sourcing bashlog preserves caller aliases and expand_aliases state" {
  run_bashlog_script <<'BASH'
    shopt -s expand_aliases
    alias info="printf caller-alias"
    before_alias="$(alias info)"
    before_shopt="$(shopt -p expand_aliases)"
    source "$1"
    after_alias="$(alias info)"
    after_shopt="$(shopt -p expand_aliases)"
    [[ ${before_alias} == "${after_alias}" ]]
    [[ ${before_shopt} == "${after_shopt}" ]]
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "sourcing bashlog does not export functions" {
  run_bashlog_script <<'BASH'
    before="$(export -f)"
    source "$1"
    after="$(export -f)"
    [[ ${before} == "${after}" ]]
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "documented public functions are defined after sourcing" {
  run_bashlog_script <<'BASH'
    source "$1"
    for name in \
      bashlog_level_get bashlog_level_set \
      bashlog_log bashlog_debug bashlog_info bashlog_notice \
      bashlog_warning bashlog_error bashlog_critical bashlog_alert \
      bashlog_emergency bashlog_redaction_add \
      bashlog_redaction_context_destroy bashlog_redact; do
      declare -F "${name}" >/dev/null || exit 1
    done
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "representative runtime behavior works with PATH unable to resolve commands" {
  run_bashlog_script <<'BASH'
    PATH=/definitely/not/a/real/path
    source "$1"
    bashlog_level_set debug || exit
    bashlog_redaction_add auth fixed secret "[REDACTED]" || exit
    bashlog_info --context auth "value=%s" secret
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info: value=[REDACTED]' ]
}
