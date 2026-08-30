#!/usr/bin/env bats

setup() {
  : "${BASHLOG_ARTIFACT:?BASHLOG_ARTIFACT must identify the artifact under test}"
}

@test "glob matcher supports basic wildcard patterns" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add ctx glob 'token-???' '[TOKEN]' || exit
    bashlog_redact ctx 'before token-abc after'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'before [TOKEN] after' ]
}

@test "glob matcher supports bracket expressions" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add ctx glob 'pin-[0-9][0-9][0-9][0-9]' '[PIN]' || exit
    bashlog_redact ctx 'pin-1234'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = '[PIN]' ]
}

@test "glob matching remains case-sensitive" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add ctx glob 'Secret?' '[R]' || exit
    bashlog_redact ctx 'secret1 Secret2'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'secret1 [R]' ]
}

@test "glob pattern capable of matching empty input is rejected" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add ctx glob '*' '[R]'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 65 ]
  [ -z "${output}" ]
}

@test "extglob operator syntax is rejected when extglob is disabled" {
  run --separate-stderr bash --noprofile --norc -c '
    shopt -u extglob
    source "$1"
    bashlog_redaction_add ctx glob '@(secret|token)' '[R]'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 65 ]
  [ -z "${output}" ]
}

@test "extglob operator syntax is rejected when extglob is enabled" {
  run --separate-stderr bash --noprofile --norc -O extglob -c '
    source "$1"
    bashlog_redaction_add ctx glob '@(secret|token)' '[R]'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 65 ]
  [ -z "${output}" ]
}

@test "ambient extglob state does not change accepted basic glob meaning" {
  run --separate-stderr bash --noprofile --norc -O extglob -c '
    source "$1"
    bashlog_redaction_add ctx glob 'token-???' '[R]' || exit
    bashlog_redact ctx 'token-abc'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = '[R]' ]
}

@test "ERE matcher redacts structured values" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add ctx ere '[0-9]{3}-[0-9]{2}-[0-9]{4}' '[SSN]' || exit
    bashlog_redact ctx 'ssn=123-45-6789'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'ssn=[SSN]' ]
}

@test "invalid ERE is rejected before context creation" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add ctx ere '[unterminated' '[R]'
    add_rc=$?
    bashlog_redact ctx 'value'
    redact_rc=$?
    printf '%s:%s\n' "${add_rc}" "${redact_rc}"
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = '65:69' ]
}

@test "ERE capable of matching empty input is rejected" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add ctx ere 'a*' '[R]'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 65 ]
  [ -z "${output}" ]
}

@test "ERE capture groups do not create replacement backreferences" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add ctx ere '(secret)-([0-9]+)' '\2-\1' || exit
    bashlog_redact ctx 'value=secret-42'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'value=\2-\1' ]
}

@test "ERE replacement ampersand remains literal" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add ctx ere 'secret-[0-9]+' '&' || exit
    bashlog_redact ctx 'value=secret-42'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'value=&' ]
}

@test "rule registration order is deterministic across matcher types" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add ctx fixed alpha beta || exit
    bashlog_redaction_add ctx ere 'beta' gamma || exit
    bashlog_redaction_add ctx glob 'gam??' delta || exit
    bashlog_redact ctx alpha
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'delta' ]
}

@test "glob and ERE matching do not mutate caller locale" {
  run --separate-stderr bash --noprofile --norc -c '
    export LC_ALL=C
    source "$1"
    before=${LC_ALL}
    bashlog_redaction_add ctx glob 'id-[[:digit:]][[:digit:]]' '[ID]' || exit
    bashlog_redaction_add ctx ere '[A-Z]{2}' '[CODE]' || exit
    bashlog_redact ctx 'id-12 AB' >/dev/null || exit
    [[ ${LC_ALL} == "${before}" ]]
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}
