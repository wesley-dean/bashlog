#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  : "${BASHLOG_ARTIFACT:?BASHLOG_ARTIFACT must identify the artifact under test}"
}

run_bashlog_script() {
  run --separate-stderr bash --noprofile --norc -s -- "${BASHLOG_ARTIFACT}" "$@"
}

run_bashlog_script_absolute() {
  run --separate-stderr /bin/bash --noprofile --norc -s -- "${BASHLOG_ARTIFACT}" "$@"
}

@test "successful protected logging emits replacement and never original fixed secret" {
  secret='ultra-distinct-secret-value-918273'

  run_bashlog_script "${secret}" <<'BASH'
    source "$1"
    secret=$2
    bashlog_redaction_add auth fixed "${secret}" '[REDACTED]' || exit
    bashlog_info --context auth 'credential=%s duplicate=%s' "${secret}" "${secret}"
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info: credential=[REDACTED] duplicate=[REDACTED]' ]
  [[ "${output}" != *"${secret}"* ]]
  [[ "${stderr}" != *"${secret}"* ]]
}

@test "every severity helper uses the same protected output boundary" {
  secret='severity-secret-49281'

  run_bashlog_script "${secret}" <<'BASH'
    source "$1"
    secret=$2
    bashlog_level_set debug || exit
    bashlog_redaction_add auth fixed "${secret}" '[R]' || exit
    bashlog_emergency --context auth '%s' "${secret}" || exit
    bashlog_alert --context auth '%s' "${secret}" || exit
    bashlog_critical --context auth '%s' "${secret}" || exit
    bashlog_error --context auth '%s' "${secret}" || exit
    bashlog_warning --context auth '%s' "${secret}" || exit
    bashlog_notice --context auth '%s' "${secret}" || exit
    bashlog_info --context auth '%s' "${secret}" || exit
    bashlog_debug --context auth '%s' "${secret}" || exit
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *"${secret}"* ]]
  [ "${stderr}" = $'emergency: [R]\nalert: [R]\ncritical: [R]\nerror: [R]\nwarning: [R]\nnotice: [R]\ninfo: [R]\ndebug: [R]' ]
}

@test "redaction covers the complete rendered record including severity label" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed info '[LEVEL]' || exit
    bashlog_info --context ctx 'message'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = '[LEVEL]: message' ]
}

@test "later replacement reintroducing earlier fixed match fails closed" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed alpha '[A]' || exit
    bashlog_redaction_add ctx fixed beta alpha || exit
    bashlog_info --context ctx '%s' beta
BASH

  [ "${status}" -eq 70 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'bashlog: message suppressed' ]
  [[ "${stderr}" != *'alpha'* ]]
  [[ "${stderr}" != *'beta'* ]]
}

@test "later replacement reintroducing earlier glob match fails closed" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx glob 'token-???' '[TOKEN]' || exit
    bashlog_redaction_add ctx fixed beta 'token-abc' || exit
    bashlog_info --context ctx '%s' beta
BASH

  [ "${status}" -eq 70 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'bashlog: message suppressed' ]
  [[ "${stderr}" != *'token-abc'* ]]
  [[ "${stderr}" != *'beta'* ]]
}

@test "later replacement reintroducing earlier ERE match fails closed" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx ere 'secret-[0-9]+' '[SECRET]' || exit
    bashlog_redaction_add ctx fixed beta 'secret-42' || exit
    bashlog_info --context ctx '%s' beta
BASH

  [ "${status}" -eq 70 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'bashlog: message suppressed' ]
  [[ "${stderr}" != *'secret-42'* ]]
  [[ "${stderr}" != *'beta'* ]]
}

@test "bashlog_redact cross-rule verification failure never returns original or failed candidate" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed alpha '[A]' || exit
    bashlog_redaction_add ctx fixed beta alpha || exit
    bashlog_redact ctx beta
BASH

  [ "${status}" -eq 70 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'bashlog: message suppressed' ]
  [[ "${stderr}" != *'alpha'* ]]
  [[ "${stderr}" != *'beta'* ]]
}

@test "failure diagnostic never reproduces original candidate or rule contents" {
  original='original-caller-secret-74741'
  earlier='protected-again-23991'

  run_bashlog_script "${original}" "${earlier}" <<'BASH'
    source "$1"
    original=$2
    earlier=$3
    bashlog_redaction_add ctx fixed "${earlier}" '[EARLIER]' || exit
    bashlog_redaction_add ctx fixed "${original}" "${earlier}" || exit
    bashlog_info --context ctx 'input=%s' "${original}"
BASH

  [ "${status}" -eq 70 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'bashlog: message suppressed' ]
  [[ "${stderr}" != *"${original}"* ]]
  [[ "${stderr}" != *"${earlier}"* ]]
  [[ "${stderr}" != *'[EARLIER]'* ]]
}

@test "diagnostic that matches active policy is suppressed completely" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed alpha '[A]' || exit
    bashlog_redaction_add ctx fixed beta alpha || exit
    bashlog_redaction_add ctx fixed 'bashlog: message suppressed' '[DIAGNOSTIC]' || exit
    bashlog_info --context ctx '%s' beta
BASH

  [ "${status}" -eq 70 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "replacement command-substitution text is data and is never executed" {
  run_bashlog_script <<'BASH'
    source "$1"
    replacement='$(printf EXECUTED >&2)'
    bashlog_redaction_add ctx fixed secret "${replacement}" || exit
    bashlog_info --context ctx '%s' secret
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info: $(printf EXECUTED >&2)' ]
}

@test "replacement parameter expansion text is data and is never expanded" {
  run_bashlog_script <<'BASH'
    source "$1"
    USER='should-not-appear'
    replacement='${USER}'
    bashlog_redaction_add ctx fixed secret "${replacement}" || exit
    bashlog_info --context ctx '%s' secret
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info: ${USER}' ]
  [[ "${stderr}" != *'should-not-appear'* ]]
}

@test "threshold-suppressed valid call does not evaluate invalid printf arguments" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_debug 'number=%d' definitely-not-a-number
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "unknown context failure never emits caller data even when safe diagnostic is optional" {
  secret='unknown-context-secret-81357'

  run_bashlog_script "${secret}" <<'BASH'
    source "$1"
    bashlog_info --context missing '%s' "$2"
BASH

  [ "${status}" -eq 69 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *"${secret}"* ]]
}

@test "redaction registration failure diagnostics never echo pattern or replacement" {
  pattern='registration-secret-pattern-111'
  replacement='registration-secret-replacement-222'

  run_bashlog_script "${pattern}" "${replacement}" <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed "$2" "$2-$3"
BASH

  [ "${status}" -eq 65 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *"${pattern}"* ]]
  [[ "${stderr}" != *"${replacement}"* ]]
}

@test "runtime redaction and logging remain functional with unusable PATH" {
  secret='path-isolation-secret-444'

  run_bashlog_script_absolute "${secret}" <<'BASH'
    PATH=/definitely/not/a/real/path
    source "$1"
    bashlog_redaction_add ctx fixed "$2" '[R]' || exit
    bashlog_info --context ctx '%s' "$2"
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info: [R]' ]
  [[ "${stderr}" != *"${secret}"* ]]
}
