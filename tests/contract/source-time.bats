#!/usr/bin/env bats

setup() {
  : "${BASHLOG_ARTIFACT:?BASHLOG_ARTIFACT must identify the artifact under test}"
}

@test "sourcing bashlog is silent on stdout and stderr" {
  run --separate-stderr bash --noprofile --norc -c 'source "$1"' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "sourcing bashlog preserves existing traps" {
  run --separate-stderr bash --noprofile --norc -c '
    trap "printf trap-fired >/dev/null" USR1
    before="$(trap -p)"
    source "$1"
    after="$(trap -p)"
    [[ ${before} == "${after}" ]]
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "sourcing bashlog preserves set shell options" {
  run --separate-stderr bash --noprofile --norc -c '
    set +e
    set -u
    set +o pipefail
    before="$(set +o)"
    source "$1"
    after="$(set +o)"
    [[ ${before} == "${after}" ]]
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "sourcing bashlog preserves shopt options" {
  run --separate-stderr bash --noprofile --norc -c '
    shopt -u extglob nullglob expand_aliases
    before="$(shopt -p)"
    source "$1"
    after="$(shopt -p)"
    [[ ${before} == "${after}" ]]
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "sourcing bashlog does not replace caller generic functions" {
  run --separate-stderr bash --noprofile --norc -c '
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
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "sourcing bashlog does not define generic convenience functions" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    for name in debug info warn warning error critical alert emergency die; do
      if declare -F "${name}" >/dev/null; then
        printf "unexpected generic function: %s\n" "${name}" >&2
        exit 1
      fi
    done
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "sourcing bashlog preserves caller aliases and expand_aliases state" {
  run --separate-stderr bash --noprofile --norc -c '
    shopt -s expand_aliases
    alias info="printf caller-alias"
    before_alias="$(alias info)"
    before_shopt="$(shopt -p expand_aliases)"
    source "$1"
    after_alias="$(alias info)"
    after_shopt="$(shopt -p expand_aliases)"
    [[ ${before_alias} == "${after_alias}" ]]
    [[ ${before_shopt} == "${after_shopt}" ]]
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "sourcing bashlog does not export functions" {
  run --separate-stderr bash --noprofile --norc -c '
    before="$(export -f)"
    source "$1"
    after="$(export -f)"
    [[ ${before} == "${after}" ]]
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "documented public functions are defined after sourcing" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    for name in \
      bashlog_level_get bashlog_level_set \
      bashlog_log bashlog_debug bashlog_info bashlog_notice \
      bashlog_warning bashlog_error bashlog_critical bashlog_alert \
      bashlog_emergency bashlog_redaction_add \
      bashlog_redaction_context_destroy bashlog_redact; do
      declare -F "${name}" >/dev/null || exit 1
    done
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "representative runtime behavior works with PATH unable to resolve commands" {
  run --separate-stderr bash --noprofile --norc -c '
    PATH=/definitely/not/a/real/path
    source "$1"
    bashlog_level_set debug || exit
    bashlog_redaction_add auth fixed secret "[REDACTED]" || exit
    bashlog_info --context auth "value=%s" secret
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info: value=[REDACTED]' ]
}
