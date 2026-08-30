#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  : "${BASHLOG_ARTIFACT:?BASHLOG_ARTIFACT must identify the artifact under test}"
}

run_bashlog_script() {
  run --separate-stderr bash --noprofile --norc -s -- "${BASHLOG_ARTIFACT}" "$@"
}

run_bashlog_script_extglob() {
  run --separate-stderr bash --noprofile --norc -O extglob -s -- "${BASHLOG_ARTIFACT}" "$@"
}

@test "glob matcher supports basic wildcard patterns" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx glob 'token-???' '[TOKEN]' || exit
    bashlog_redact ctx 'before token-abc after'
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'before [TOKEN] after' ]
}

@test "glob matcher supports bracket expressions" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx glob 'pin-[0-9][0-9][0-9][0-9]' '[PIN]' || exit
    bashlog_redact ctx 'pin-1234'
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = '[PIN]' ]
}

@test "glob matching remains case-sensitive" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx glob 'Secret?' '[R]' || exit
    bashlog_redact ctx 'secret1 Secret2'
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'secret1 [R]' ]
}

@test "glob pattern capable of matching empty input is rejected" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx glob '*' '[R]'
BASH
  [ "${status}" -eq 65 ]
  [ -z "${output}" ]
}

@test "extglob operator syntax is rejected when extglob is disabled" {
  run_bashlog_script <<'BASH'
    shopt -u extglob
    source "$1"
    bashlog_redaction_add ctx glob '@(secret|token)' '[R]'
BASH
  [ "${status}" -eq 65 ]
  [ -z "${output}" ]
}

@test "extglob operator syntax is rejected when extglob is enabled" {
  run_bashlog_script_extglob <<'BASH'
    source "$1"
    bashlog_redaction_add ctx glob '@(secret|token)' '[R]'
BASH
  [ "${status}" -eq 65 ]
  [ -z "${output}" ]
}

@test "ambient extglob state does not change accepted basic glob meaning" {
  run_bashlog_script_extglob <<'BASH'
    source "$1"
    bashlog_redaction_add ctx glob 'token-???' '[R]' || exit
    bashlog_redact ctx 'token-abc'
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = '[R]' ]
}

@test "ERE matcher redacts structured values" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx ere '[0-9]{3}-[0-9]{2}-[0-9]{4}' '[SSN]' || exit
    bashlog_redact ctx 'ssn=123-45-6789'
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'ssn=[SSN]' ]
}

@test "anchored ERE locates the match selected against the complete input" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx ere 'foo$' '[END]' || exit
    bashlog_redact ctx 'foo middle foo'
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'foo middle [END]' ]
}

@test "start-anchored ERE does not match an identical later substring" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx ere '^foo' '[START]' || exit
    bashlog_redact ctx 'foo middle foo'
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = '[START] middle foo' ]
}

@test "invalid ERE is rejected before context creation" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx ere '[unterminated' '[R]'
    add_rc=$?
    bashlog_redact ctx 'value'
    redact_rc=$?
    printf '%s:%s\n' "${add_rc}" "${redact_rc}"
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = '65:69' ]
}

@test "ERE capable of matching empty input is rejected" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx ere 'a*' '[R]'
BASH
  [ "${status}" -eq 65 ]
  [ -z "${output}" ]
}

@test "ERE capture groups do not create replacement backreferences" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx ere '(secret)-([0-9]+)' '\2-\1' || exit
    bashlog_redact ctx 'value=secret-42'
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'value=\2-\1' ]
}

@test "ERE replacement ampersand remains literal" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx ere 'secret-[0-9]+' '&' || exit
    bashlog_redact ctx 'value=secret-42'
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'value=&' ]
}

@test "ambient nocasematch does not weaken case-sensitive glob and ERE semantics" {
  run_bashlog_script <<'BASH'
    shopt -s nocasematch
    source "$1"
    bashlog_redaction_add ctx glob 'Secret?' '[G]' || exit
    bashlog_redaction_add ctx ere 'Token[0-9]+' '[E]' || exit
    value="$(bashlog_redact ctx 'secret1 Secret2 token3 Token4')" || exit
    shopt -q nocasematch || exit 1
    printf '%s\n' "${value}"
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'secret1 [G] token3 [E]' ]
  [ -z "${stderr}" ]
}

@test "rule registration order is deterministic across matcher types" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed alpha beta || exit
    bashlog_redaction_add ctx ere 'beta' gamma || exit
    bashlog_redaction_add ctx glob 'gam??' delta || exit
    bashlog_redact ctx alpha
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'delta' ]
}

@test "glob and ERE matching do not mutate caller locale" {
  run_bashlog_script <<'BASH'
    export LC_ALL=C
    source "$1"
    before=${LC_ALL}
    bashlog_redaction_add ctx glob 'id-[[:digit:]][[:digit:]]' '[ID]' || exit
    bashlog_redaction_add ctx ere '[A-Z]{2}' '[lower]' || exit
    bashlog_redact ctx 'id-12 AB' >/dev/null || exit
    [[ ${LC_ALL} == "${before}" ]]
BASH
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}
