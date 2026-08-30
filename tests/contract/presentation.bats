#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  : "${BASHLOG_ARTIFACT:?BASHLOG_ARTIFACT must identify the artifact under test}"
}

run_bashlog_script() {
  run --separate-stderr bash --noprofile --norc -s -- "${BASHLOG_ARTIFACT}" "$@"
}

@test "presentation defaults are auto format, off timestamp, and auto color" {
  run_bashlog_script <<'BASH'
    source "$1"
    printf '%s\n' "$(bashlog_format_get)" "$(bashlog_timestamp_get)" "$(bashlog_color_get)"
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = $'auto\noff\nauto' ]
  [ -z "${stderr}" ]
}

@test "presentation setters reject invalid modes atomically" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_timestamp_set utc || exit
    bashlog_color_set never || exit

    bashlog_format_set invalid
    format_status=$?
    bashlog_timestamp_set invalid
    timestamp_status=$?
    bashlog_color_set invalid
    color_status=$?

    printf '%s:%s:%s:%s:%s:%s\n' \
      "${format_status}" "$(bashlog_format_get)" \
      "${timestamp_status}" "$(bashlog_timestamp_get)" \
      "${color_status}" "$(bashlog_color_get)"
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = '64:human:64:utc:64:never' ]
  [ -z "${stderr}" ]
}

@test "default severity style palette is documented and queryable" {
  run_bashlog_script <<'BASH'
    source "$1"
    for level in emergency alert critical error warning notice info debug; do
      printf '%s=%s\n' "${level}" "$(bashlog_level_style_get "${level}")" || exit
    done
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = $'emergency=red bold\nalert=red bold\ncritical=red bold\nerror=red normal\nwarning=yellow normal\nnotice=cyan normal\ninfo=green normal\ndebug=default dim' ]
  [ -z "${stderr}" ]
}

@test "severity style getter accepts numeric and named forms for same level" {
  run_bashlog_script <<'BASH'
    source "$1"
    printf '%s\n' "$(bashlog_level_style_get critical)" "$(bashlog_level_style_get 2)"
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = $'red bold\nred bold' ]
  [ -z "${stderr}" ]
}

@test "severity style setter overrides color and intensity atomically" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_level_style_set error magenta bold || exit
    before="$(bashlog_level_style_get error)" || exit
    bashlog_level_style_set error ultraviolet bold
    bad_color_status=$?
    after_bad_color="$(bashlog_level_style_get error)" || exit
    bashlog_level_style_set error cyan blinking
    bad_intensity_status=$?
    after_bad_intensity="$(bashlog_level_style_get error)" || exit
    printf '%s|%s|%s|%s|%s\n' \
      "${before}" "${bad_color_status}" "${after_bad_color}" \
      "${bad_intensity_status}" "${after_bad_intensity}"
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'magenta bold|64|magenta bold|64|magenta bold' ]
  [ -z "${stderr}" ]
}

@test "severity style reset restores one level without changing another" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_level_style_set error magenta bold || exit
    bashlog_level_style_set warning blue dim || exit
    bashlog_level_style_reset error || exit
    printf '%s|%s\n' \
      "$(bashlog_level_style_get error)" \
      "$(bashlog_level_style_get warning)"
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'red normal|blue dim' ]
  [ -z "${stderr}" ]
}

@test "severity style reset with no level restores complete default palette" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_level_style_set emergency white normal || exit
    bashlog_level_style_set debug red bold || exit
    bashlog_level_style_reset || exit
    printf '%s|%s\n' \
      "$(bashlog_level_style_get emergency)" \
      "$(bashlog_level_style_get debug)"
BASH

  [ "${status}" -eq 0 ]
  [ "${output}" = 'red bold|default dim' ]
  [ -z "${stderr}" ]
}

@test "default auto format uses logfmt when stderr is not a TTY" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_info "This is an info message."
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'level=info msg="This is an info message."' ]
}

@test "explicit human format preserves compact severity message form" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info "This is an info message."
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info: This is an info message.' ]
}

@test "explicit logfmt is machine-oriented even when color is forced always" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set logfmt || exit
    bashlog_color_set always || exit
    bashlog_warning 'connection delayed'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'level=warning msg="connection delayed"' ]
  [[ "${stderr}" != *$'\033['* ]]
}

@test "human color always decorates only the severity token" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set always || exit
    bashlog_info 'application started'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = $'\033[32minfo\033[0m: application started' ]
}

@test "critical defaults to bold red and reset immediately follows severity" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set always || exit
    bashlog_critical --tag storage 'filesystem unavailable'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = $'\033[1;31mcritical\033[0m [storage]: filesystem unavailable' ]
}

@test "overridden severity style changes only the signifier" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set always || exit
    bashlog_level_style_set error magenta bold || exit
    bashlog_error --tag api 'request failed'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = $'\033[1;35merror\033[0m [api]: request failed' ]
}

@test "default normal style emits no bashlog-owned ANSI bytes for that severity" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set always || exit
    bashlog_level_style_set warning default normal || exit
    bashlog_warning 'plain signifier'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'warning: plain signifier' ]
  [[ "${stderr}" != *$'\033['* ]]
}

@test "logfmt ignores per-level style overrides even when color is always" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set logfmt || exit
    bashlog_color_set always || exit
    bashlog_level_style_set error magenta bold || exit
    bashlog_error 'request failed'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'level=error msg="request failed"' ]
  [[ "${stderr}" != *$'\033['* ]]
}

@test "human color auto emits no ANSI when stderr is not a TTY" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set auto || exit
    bashlog_warning 'plain redirected warning'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'warning: plain redirected warning' ]
  [[ "${stderr}" != *$'\033['* ]]
}

@test "human renderer preserves repeated tag order" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_warning --tag api --tag retry 'request delayed'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'warning [api] [retry]: request delayed' ]
}

@test "logfmt renderer preserves repeated tag order" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set logfmt || exit
    bashlog_warning --tag api --tag retry 'request delayed'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'level=warning tag=api tag=retry msg="request delayed"' ]
}

@test "invalid tag syntax returns 64 before caller message emission" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_info --tag 'bad tag' 'caller-secret-value'
BASH

  [ "${status}" -eq 64 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'caller-secret-value'* ]]
}

@test "invalid tag syntax is still rejected before threshold suppression" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_debug --tag 'bad tag' 'caller-secret-value'
BASH

  [ "${status}" -eq 64 ]
  [ -z "${output}" ]
  [[ "${stderr}" != *'caller-secret-value'* ]]
}

@test "option terminator separates context and tag options from leading dash format" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_redaction_add secrets fixed secret-value REDACTED || exit
    bashlog_info --tag auth --context secrets -- '-token=%s' secret-value
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info [auth]: -token=REDACTED' ]
}

@test "registered contexts remain inert when logging omits context" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_redaction_add secrets fixed token REDACTED || exit
    bashlog_info 'token=%s' token
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info: token=token' ]
}

@test "caller-managed redaction can be logged without selecting context again" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_redaction_add secrets fixed secret-value REDACTED || exit
    clean="$(bashlog_redact secrets 'token=secret-value')" || exit
    bashlog_info '%s' "${clean}"
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info: token=REDACTED' ]
}

@test "logger-managed context redacts formatted message before human rendering" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_redaction_add secrets fixed secret-value REDACTED || exit
    bashlog_info --context secrets 'token=%s' secret-value
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info: token=REDACTED' ]
}

@test "logger-managed context redacts tags before logfmt rendering" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set logfmt || exit
    bashlog_redaction_add secrets fixed secret REDACTED || exit
    bashlog_info --context secrets --tag secret 'message'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'level=info tag=REDACTED msg="message"' ]
}

@test "final verification includes library-generated severity without transforming it" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set logfmt || exit
    bashlog_redaction_add policy fixed 'level=info' REDACTED || exit
    bashlog_info --context policy 'message'
BASH

  [ "${status}" -eq 70 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'bashlog: message suppressed' ]
}

@test "UTC timestamp is generated with second precision" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set logfmt || exit
    bashlog_timestamp_set utc || exit
    bashlog_info 'timestamped'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [[ "${stderr}" =~ ^ts=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\ level=info\ msg=\"timestamped\"$ ]]
}

@test "local timestamp includes numeric UTC offset" {
  run_bashlog_script <<'BASH'
    export TZ=UTC0
    source "$1"
    bashlog_format_set logfmt || exit
    bashlog_timestamp_set local || exit
    bashlog_info 'timestamped'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [[ "${stderr}" =~ ^ts=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+0000\ level=info\ msg=\"timestamped\"$ ]]
}

@test "UTC timestamp generation preserves caller TZ value" {
  run_bashlog_script <<'BASH'
    export TZ=EST5EDT
    source "$1"
    before=${TZ}
    bashlog_format_set logfmt || exit
    bashlog_timestamp_set utc || exit
    bashlog_info 'timestamped' || exit
    [[ ${TZ} == "${before}" ]]
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [[ "${stderr}" =~ ^ts=.*Z\ level=info\ msg=\"timestamped\"$ ]]
}

@test "threshold suppression occurs before timestamp acquisition" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_timestamp_set utc || exit
    __bashlog_timestamp_acquire() {
      printf '%s\n' 'timestamp-acquired-unexpectedly' >&2
      return 70
    }
    bashlog_debug 'hidden'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "logfmt escapes quotes backslashes tabs carriage returns and newlines" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set logfmt || exit
    bashlog_info '%s' $'quote=" slash=\\ tab=\t cr=\r nl=\n'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'level=info msg="quote=\" slash=\\ tab=\t cr=\r nl=\n"' ]
}

@test "logfmt escapes other ASCII control bytes with uppercase unicode form" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set logfmt || exit
    bashlog_info '%s' $'before\x01after'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'level=info msg="before\u0001after"' ]
}

@test "logfmt preserves representable multibyte message text" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set logfmt || exit
    bashlog_info '%s' 'café 東京 🙂'
BASH

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'level=info msg="café 東京 🙂"' ]
}
