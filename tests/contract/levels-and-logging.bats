#!/usr/bin/env bats

setup() {
  : "${BASHLOG_ARTIFACT:?BASHLOG_ARTIFACT must identify the artifact under test}"
}

@test "default threshold is canonical info" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_level_get
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'info' ]
  [ -z "${stderr}" ]
}

@test "bashlog_level_get rejects arguments without writing a value" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_level_get unexpected
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 64 ]
  [ -z "${output}" ]
}

@test "canonical severity names and numeric thresholds round-trip" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    names=(emergency alert critical error warning notice info debug)
    for number in 0 1 2 3 4 5 6 7; do
      bashlog_level_set "${number}" || exit
      bashlog_level_get || exit
      bashlog_level_set "${names[number]}" || exit
      bashlog_level_get || exit
    done
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'emergency\nemergency\nalert\nalert\ncritical\ncritical\nerror\nerror\nwarning\nwarning\nnotice\nnotice\ninfo\ninfo\ndebug\ndebug' ]
  [ -z "${stderr}" ]
}

@test "level names are case-sensitive and aliases are rejected" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_level_set INFO && exit 1
    [[ $? -eq 64 ]] || exit
    bashlog_level_set warn && exit 1
    [[ $? -eq 64 ]] || exit
    bashlog_level_set err && exit 1
    [[ $? -eq 64 ]] || exit
    bashlog_level_get
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'info' ]
}

@test "failed threshold update leaves previous threshold unchanged" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_level_set warning || exit
    bashlog_level_set definitely-invalid
    rc=$?
    current="$(bashlog_level_get)" || exit
    printf '%s:%s\n' "${rc}" "${current}"
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = '64:warning' ]
  [ -z "${stderr}" ]
}

@test "successful threshold update is silent" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_level_set warning
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "default threshold emits info and suppresses debug" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_debug 'hidden' || exit
    bashlog_info 'visible'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info: visible' ]
}

@test "warning threshold emits warning and suppresses info" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_level_set warning || exit
    bashlog_info 'hidden' || exit
    bashlog_warning 'visible'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'warning: visible' ]
}

@test "threshold zero permits emergency and suppresses alert" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_level_set 0 || exit
    bashlog_alert 'hidden' || exit
    bashlog_emergency 'visible'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'emergency: visible' ]
}

@test "threshold seven permits debug" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_level_set 7 || exit
    bashlog_debug 'visible'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'debug: visible' ]
}

@test "all severity helpers render canonical lowercase names" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_level_set debug || exit
    bashlog_emergency emergency-message || exit
    bashlog_alert alert-message || exit
    bashlog_critical critical-message || exit
    bashlog_error error-message || exit
    bashlog_warning warning-message || exit
    bashlog_notice notice-message || exit
    bashlog_info info-message || exit
    bashlog_debug debug-message || exit
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = $'emergency: emergency-message\nalert: alert-message\ncritical: critical-message\nerror: error-message\nwarning: warning-message\nnotice: notice-message\ninfo: info-message\ndebug: debug-message' ]
}

@test "generic logger uses the same canonical rendering as helpers" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_log warning 'configuration=%s' legacy
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'warning: configuration=legacy' ]
}

@test "generic logger rejects severity aliases" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_log warn 'caller-secret-value'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 64 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'caller-secret-value'* ]]
}

@test "printf-style arguments construct the message before emission" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_info 'user=%s count=%d percent=%%' alice 7
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info: user=alice count=7 percent=%' ]
}

@test "option terminator permits a format string beginning with dash" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_info -- '--literal-leading-dash=%s' value
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info: --literal-leading-dash=value' ]
}

@test "leading-dash format without option terminator is rejected as option syntax" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_info '--caller-secret-value'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 64 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'caller-secret-value'* ]]
}

@test "unknown logging option returns 64 without emitting caller message" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_info --unknown-option 'caller-secret-value'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 64 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'caller-secret-value'* ]]
}

@test "missing format string returns 64" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_info
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 64 ]
  [ -z "${output}" ]
}

@test "invalid requested context identifier returns 64 before threshold suppression" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_debug --context 'bad context' 'caller-secret-value'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 64 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'caller-secret-value'* ]]
}

@test "unknown requested context returns 69 before threshold suppression" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_debug --context missing 'caller-secret-value'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 69 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'caller-secret-value'* ]]
}

@test "omitting context leaves context redaction opt-in" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_redaction_add auth fixed secret '[REDACTED]' || exit
    bashlog_info 'value=%s' secret
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info: value=secret' ]
}

@test "embedded newline is preserved rather than silently normalized" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_info '%s' $'first\nsecond'
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = $'info: first\nsecond' ]
}

@test "printf formatting error returns 64 and does not emit a log record" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_info 'number=%d' definitely-not-a-number
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 64 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'info: number='* ]]
}

@test "final stderr emission failure returns 74" {
  run --separate-stderr bash --noprofile --norc -c '
    source "$1"
    bashlog_info 'cannot-be-written' 2>&-
    rc=$?
    printf '%s\n' "${rc}"
  ' _ "${BASHLOG_ARTIFACT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = '74' ]
  [ -z "${stderr}" ]
}
