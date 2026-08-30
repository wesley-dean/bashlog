#!/usr/bin/env bats

setup() {
  : "${BASHLOG_ARTIFACT:?BASHLOG_ARTIFACT must identify the artifact under test}"
}

@test "first successful rule registration creates context atomically" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add auth fixed secret '[REDACTED]' || exit
    bashlog_redact auth 'value=secret'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'value=[REDACTED]' ]
  [ -z "${stderr}" ]
}

@test "failed first rule registration leaves unseen context unavailable" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add auth fixed '' '[REDACTED]'
    add_rc=$?
    bashlog_redact auth 'value=secret'
    redact_rc=$?
    printf '%s:%s\n' "${add_rc}" "${redact_rc}"
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = '65:69' ]
  [[ "${stderr}" != *'secret'* ]]
}

@test "active context accepts additional rules after prior use" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add auth fixed alpha '[A]' || exit
    first="$(bashlog_redact auth 'alpha beta')" || exit
    bashlog_redaction_add auth fixed beta '[B]' || exit
    second="$(bashlog_redact auth 'alpha beta')" || exit
    printf '%s\n%s\n' "${first}" "${second}"
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'[A] beta\n[A] [B]' ]
  [ -z "${stderr}" ]
}

@test "context rules remain append-only in successful registration order" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add ctx fixed alpha beta || exit
    bashlog_redaction_add ctx fixed beta gamma || exit
    bashlog_redact ctx alpha
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'gamma' ]
  [ -z "${stderr}" ]
}

@test "duplicate matcher and pattern pair is rejected without changing context" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add ctx fixed secret '[ONE]' || exit
    bashlog_redaction_add ctx fixed secret '[TWO]'
    duplicate_rc=$?
    value="$(bashlog_redact ctx secret)" || exit
    printf '%s:%s\n' "${duplicate_rc}" "${value}"
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = '65:[ONE]' ]
  [[ "${stderr}" != *'secret'* ]]
}

@test "same pattern may be registered under a different matcher type" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add ctx fixed 'abc' '[FIXED]' || exit
    bashlog_redaction_add ctx ere 'abc' '[ERE]' || exit
    bashlog_redact ctx 'abc'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = '[FIXED]' ]
}

@test "valid context identifier grammar accepts representative punctuation" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    for context in auth _private auth_v1 request-42 api.client:west; do
      bashlog_redaction_add "${context}" fixed secret '[R]' || exit
      value="$(bashlog_redact "${context}" secret)" || exit
      [[ ${value} == '[R]' ]] || exit 1
    done
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "invalid context identifier grammar is rejected" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    for context in '' '9starts-with-digit' 'has space' 'has/slash' '$bad' 'semi;colon'; do
      bashlog_redaction_add "${context}" fixed secret '[R]'
      [[ $? -eq 64 ]] || exit 1
    done
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'secret'* ]]
}

@test "successful context destruction makes context unavailable" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_redaction_context_destroy auth || exit
    bashlog_redact auth secret
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 69 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'secret'* ]]
}

@test "destroyed context name cannot be reused" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_redaction_context_destroy auth || exit
    bashlog_redaction_add auth fixed replacement '[NEW]'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 69 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'replacement'* ]]
}

@test "destroying unknown context returns 69" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_context_destroy missing
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 69 ]
  [ -z "${output}" ]
}

@test "destroying an already destroyed context returns 69" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_redaction_context_destroy auth || exit
    bashlog_redaction_context_destroy auth
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 69 ]
  [ -z "${output}" ]
}

@test "successful add and destroy operations produce no routine output" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_redaction_context_destroy auth
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "unknown explicitly requested logging context fails closed" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_info --context missing 'caller-secret-value'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 69 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'caller-secret-value'* ]]
}

@test "destroyed explicitly requested logging context fails closed" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_redaction_context_destroy auth || exit
    bashlog_info --context auth 'caller-secret-value'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 69 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'caller-secret-value'* ]]
}
