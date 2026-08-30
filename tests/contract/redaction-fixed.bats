#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  : "${BASHLOG_ARTIFACT:?BASHLOG_ARTIFACT must identify the artifact under test}"
}

run_bashlog_script() {
  run --separate-stderr bash --noprofile --norc -s -- "${BASHLOG_ARTIFACT}" "$@"
}

@test "fixed matcher treats glob and ERE metacharacters literally" {
  run_bashlog_script <<'BASH'
    source "$1"
    pattern='a.*[b]?^$'
    bashlog_redaction_add ctx fixed "${pattern}" '[R]' || exit
    bashlog_redact ctx "before ${pattern} after"
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'before [R] after' ]
  [ -z "${stderr}" ]
}

@test "fixed matcher replaces multiple non-overlapping occurrences" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed secret '[R]' || exit
    bashlog_redact ctx 'secret / secret / secret'
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = '[R] / [R] / [R]' ]
  [ -z "${stderr}" ]
}

@test "fixed matcher handles adjacent occurrences" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed xy Z || exit
    bashlog_redact ctx xyxyxy
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'ZZZ' ]
}

@test "fixed matcher uses leftmost non-overlapping progression" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed aaa X || exit
    bashlog_redact ctx aaaaa
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'Xaa' ]
}

@test "empty fixed pattern is rejected" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed '' '[R]'
BASH

  [ "${status}" -eq 65 ]
  [ -z "${output}" ]
}

@test "empty fixed replacement removes matches" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed secret '' || exit
    bashlog_redact ctx 'before-secret-after'
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'before--after' ]
}

@test "self-matching fixed replacement is rejected" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed secret 'still-secret-here'
BASH

  [ "${status}" -eq 65 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'still-secret-here'* ]]
  [[ "${stderr}" != *'secret'* ]]
}

@test "replacement ampersand remains literal" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed secret '&' || exit
    bashlog_redact ctx 'value=secret'
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'value=&' ]
}

@test "replacement backreference text remains literal" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed secret '\1' || exit
    bashlog_redact ctx 'value=secret'
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'value=\1' ]
}

@test "replacement parameter and command substitution text remains literal" {
  run_bashlog_script <<'BASH'
    source "$1"
    replacement='${USER}-$(id)-$HOME'
    bashlog_redaction_add ctx fixed secret "${replacement}" || exit
    bashlog_redact ctx 'value=secret'
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'value=${USER}-$(id)-$HOME' ]
}

@test "replacement glob metacharacters remain literal" {
  run_bashlog_script <<'BASH'
    source "$1"
    replacement='*?[]'
    bashlog_redaction_add ctx fixed secret "${replacement}" || exit
    bashlog_redact ctx 'value=secret'
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'value=*?[]' ]
}

@test "fixed matcher redacts accented Latin exact sequence" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed 'café' '[R]' || exit
    bashlog_redact ctx 'before café after'
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'before [R] after' ]
}

@test "fixed matcher redacts Cyrillic exact sequence" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed 'секрет' '[R]' || exit
    bashlog_redact ctx 'значение=секрет'
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'значение=[R]' ]
}

@test "fixed matcher redacts CJK exact sequence" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed '秘密' '[R]' || exit
    bashlog_redact ctx '値=秘密'
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = '値=[R]' ]
}

@test "fixed matcher redacts emoji exact sequence" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed '🔐secret🔑' '[R]' || exit
    bashlog_redact ctx 'before 🔐secret🔑 after'
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'before [R] after' ]
}

@test "fixed matcher redacts exact combining sequence" {
  run_bashlog_script <<'BASH'
    source "$1"
    combining='é'
    bashlog_redaction_add ctx fixed "${combining}" '[R]' || exit
    bashlog_redact ctx "before ${combining} after"
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'before [R] after' ]
}

@test "fixed matcher does not claim Unicode normalization equivalence" {
  run_bashlog_script <<'BASH'
    source "$1"
    precomposed='é'
    decomposed='é'
    bashlog_redaction_add ctx fixed "${precomposed}" '[R]' || exit
    bashlog_redact ctx "${decomposed}"
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'é' ]
}

@test "bashlog_redact adds no newline to successful stdout" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed secret '[R]' || exit
    value="$(bashlog_redact ctx secret)" || exit
    printf '<%s>' "${value}"
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = '<[R]>' ]
  [ -z "${stderr}" ]
}

@test "bashlog_redact never writes original input to stdout on unavailable context" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redact missing 'caller-secret-value'
BASH

  [ "${status}" -eq 69 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'caller-secret-value'* ]]
}
