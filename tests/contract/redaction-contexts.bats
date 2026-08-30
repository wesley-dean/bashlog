#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  : "${BASHLOG_ARTIFACT:?BASHLOG_ARTIFACT must identify the artifact under test}"
}

run_bashlog_script() {
  run --separate-stderr bash --noprofile --norc -s -- "${BASHLOG_ARTIFACT}" "$@"
}

@test "first successful rule registration creates context atomically" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add auth fixed secret '[REDACTED]' || exit
    bashlog_redact auth 'value=secret'
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'value=[REDACTED]' ]
  [ -z "${stderr}" ]
}

@test "failed first rule registration leaves unseen context unavailable" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add auth fixed '' '[REDACTED]'
    add_rc=$?
    bashlog_redact auth 'value=secret'
    redact_rc=$?
    printf '%s:%s\n' "${add_rc}" "${redact_rc}"
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = '65:69' ]
  [[ "${stderr}" != *'secret'* ]]
}

@test "active context accepts additional rules after prior use" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add auth fixed alpha '[A]' || exit
    first="$(bashlog_redact auth 'alpha beta')" || exit
    bashlog_redaction_add auth fixed beta '[B]' || exit
    second="$(bashlog_redact auth 'alpha beta')" || exit
    printf '%s\n%s\n' "${first}" "${second}"
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = $'[A] beta\n[A] [B]' ]
  [ -z "${stderr}" ]
}

@test "context rules remain append-only in successful registration order" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed alpha beta || exit
    bashlog_redaction_add ctx fixed beta gamma || exit
    bashlog_redact ctx alpha
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'gamma' ]
  [ -z "${stderr}" ]
}

@test "duplicate matcher and pattern pair is rejected without changing context" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed secret '[ONE]' || exit
    bashlog_redaction_add ctx fixed secret '[TWO]'
    duplicate_rc=$?
    value="$(bashlog_redact ctx secret)" || exit
    printf '%s:%s\n' "${duplicate_rc}" "${value}"
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = '65:[ONE]' ]
  [[ "${stderr}" != *'secret'* ]]
}

@test "same pattern may be registered under a different matcher type" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed 'abc' '[FIXED]' || exit
    bashlog_redaction_add ctx ere 'abc' '[ERE]' || exit
    bashlog_redact ctx 'abc'
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = '[FIXED]' ]
}

@test "valid context identifier grammar accepts representative punctuation" {
  run_bashlog_script <<'BASH'
    source "$1"
    for context in auth _private auth_v1 request-42 api.client:west; do
      bashlog_redaction_add "${context}" fixed secret '[R]' || exit
      value="$(bashlog_redact "${context}" secret)" || exit
      [[ ${value} == '[R]' ]] || exit 1
    done
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "invalid context identifier grammar is rejected" {
  run_bashlog_script <<'BASH'
    source "$1"
    for context in '' '9starts-with-digit' 'has space' 'has/slash' '$bad' 'semi;colon'; do
      bashlog_redaction_add "${context}" fixed secret '[R]'
      [[ $? -eq 64 ]] || exit 1
    done
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'secret'* ]]
}

@test "successful context destruction makes context unavailable" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_redaction_context_destroy auth || exit
    bashlog_redact auth secret
BASH

  [ "${status}" -eq 69 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'secret'* ]]
}

@test "destroyed context name cannot be reused" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_redaction_context_destroy auth || exit
    bashlog_redaction_add auth fixed replacement '[NEW]'
BASH

  [ "${status}" -eq 69 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'replacement'* ]]
}

@test "destroying unknown context returns 69" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_context_destroy missing
BASH

  [ "${status}" -eq 69 ]
  [ -z "${output}" ]
}

@test "destroying an already destroyed context returns 69" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_redaction_context_destroy auth || exit
    bashlog_redaction_context_destroy auth
BASH

  [ "${status}" -eq 69 ]
  [ -z "${output}" ]
}

@test "successful add and destroy operations produce no routine output" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_redaction_context_destroy auth
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "unknown explicitly requested logging context fails closed" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_info --context missing 'caller-secret-value'
BASH

  [ "${status}" -eq 69 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'caller-secret-value'* ]]
}

@test "destroyed explicitly requested logging context fails closed" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_redaction_context_destroy auth || exit
    bashlog_info --context auth 'caller-secret-value'
BASH

  [ "${status}" -eq 69 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'caller-secret-value'* ]]
}
