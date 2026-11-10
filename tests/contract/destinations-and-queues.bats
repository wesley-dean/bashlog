#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  : "${BASHLOG_ARTIFACT:?BASHLOG_ARTIFACT must identify the artifact under test}"
}

run_bashlog_script() {
  run --separate-stderr bash --noprofile --norc -s -- "${BASHLOG_ARTIFACT}" "$@"
}

@test "default logging remains stderr while explicit STDOUT is opt-in" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info 'ordinary'
    bashlog_warning --to STDOUT 'intentional'
    bashlog_error --to STDERR 'explicit'
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'warning: intentional' ]
  [ "${stderr}" = $'info: ordinary\nerror: explicit' ]
}

@test "all eight severity helpers route through named queues in order" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_level_set debug || exit
    bashlog_emergency --to queue:Eight a || exit
    bashlog_alert --to queue:Eight b || exit
    bashlog_critical --to queue:Eight c || exit
    bashlog_error --to queue:Eight d || exit
    bashlog_warning --to queue:Eight e || exit
    bashlog_notice --to queue:Eight f || exit
    bashlog_info --to queue:Eight g || exit
    bashlog_debug --to queue:Eight h || exit
    bashlog_queue_flush Eight --to STDOUT
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = $'emergency: a\nalert: b\ncritical: c\nerror: d\nwarning: e\nnotice: f\ninfo: g\ndebug: h' ]
  [ -z "${stderr}" ]
}

@test "generic logger supports mixed option order and terminator" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_log warning --tag api --to queue:Warn -- '--leading=%s' text || exit
    bashlog_queue_flush Warn
BASH
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'warning [api]: --leading=text' ]
}

@test "destination grammar accepts only uppercase streams and ASCII alphanumeric queues" {
  run_bashlog_script <<'BASH'
    source "$1"
    for destination in stderr stdout queue: queue:bad_name queue:bad-name queue:Mixed.name queue:a/b queue:bad:part file:path 'queue:bad name' 'queue:é'; do
      bashlog_info --to "${destination}" 'caller-secret' && exit 1
      [[ $? -eq 64 ]] || exit 2
    done
    bashlog_info --to queue:A1 'ok' || exit 3
    bashlog_queue_clear A1
BASH
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "destination parsing rejects missing and repeated --to before threshold" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_info --to && exit 1
    [[ $? -eq 64 ]] || exit 2
    bashlog_info --to STDERR --to STDOUT 'secret' && exit 3
    [[ $? -eq 64 ]] || exit 4
    bashlog_info --to queue:A --to queue:B 'secret' && exit 5
    [[ $? -eq 64 ]] || exit 6
    bashlog_debug --to not-valid 'suppressed-secret' && exit 7
    [[ $? -eq 64 ]] || exit 8
    bashlog_queue_flush A
    bashlog_queue_flush B
BASH
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "valid debug suppression does not create a queued record" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_debug --to queue:hidden '%d' invalid-integer || exit
    bashlog_queue_flush hidden
BASH
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "case-sensitive queues are separate and preserve FIFO order" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:Errors first || exit
    bashlog_info --to queue:errors second || exit
    bashlog_info --to queue:Errors third || exit
    bashlog_queue_flush Errors --to STDOUT || exit
    bashlog_queue_flush errors --to STDERR
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = $'info: first\ninfo: third' ]
  [ "${stderr}" = 'info: second' ]
}

@test "flush defaults to STDERR and clears only the selected queue" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:keep 'retained' || exit
    bashlog_info --to queue:discard 'removed' || exit
    bashlog_queue_clear discard || exit
    bashlog_queue_flush keep || exit
    bashlog_queue_flush keep || exit
    bashlog_queue_flush discard
BASH
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'info: retained' ]
}

@test "empty and never-created queues flush and clear successfully" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_queue_flush Unknown || exit
    bashlog_queue_flush Unknown --to STDOUT || exit
    bashlog_queue_clear Unknown || exit
    bashlog_info --to queue:Once hello || exit
    bashlog_queue_clear Once || exit
    bashlog_queue_flush Once
BASH
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "queue management rejects invalid names and destinations without consuming" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:Good 'kept' || exit
    for command in flush clear; do
      bashlog_queue_"${command}" 'Bad_Name' && exit 1
      [[ $? -eq 64 ]] || exit 2
      bashlog_queue_"${command}" 'queue:Good' && exit 3
      [[ $? -eq 64 ]] || exit 4
    done
    for destination in queue:Other stdout stderr bad; do
      bashlog_queue_flush Good --to "${destination}" && exit 5
      [[ $? -eq 64 ]] || exit 6
    done
    bashlog_queue_flush Good --to STDOUT
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'info: kept' ]
  [ -z "${stderr}" ]
}

@test "invalid queue flush syntax does not discard valid messages" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:Keep present || exit
    bashlog_queue_flush Keep --to && exit 1
    [[ $? -eq 64 ]] || exit 2
    bashlog_queue_flush Keep --unknown STDOUT && exit 3
    [[ $? -eq 64 ]] || exit 4
    bashlog_queue_flush Keep --to STDOUT extra && exit 5
    [[ $? -eq 64 ]] || exit 6
    bashlog_queue_flush Keep --to STDOUT
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'info: present' ]
  [ -z "${stderr}" ]
}

@test "failed queue flush reports 74 and retains every record for retry" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:Fail first || exit
    bashlog_warning --to queue:Fail second || exit
    bashlog_queue_flush Fail --to STDERR 2>&- && exit 1
    [[ $? -eq 74 ]] || exit 2
    bashlog_queue_flush Fail --to STDOUT
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = $'info: first\nwarning: second' ]
  [ -z "${stderr}" ]
}

@test "explicit STDOUT write failure returns 74" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_info --to STDOUT cannot-write 1>&-
BASH
  [ "${status}" -eq 74 ]
  [ -z "${output}" ]
}

@test "queued messages are rendered before flushing and ignore later style changes" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_warning --to queue:Frozen --tag api 'saved' || exit
    bashlog_format_set logfmt || exit
    bashlog_color_set always || exit
    bashlog_queue_flush Frozen --to STDOUT
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'warning [api]: saved' ]
  [ -z "${stderr}" ]
}

@test "auto formatting for non-TTY queue and STDOUT is deterministic logfmt" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_info --to queue:Auto 'queued' || exit
    bashlog_info --to STDOUT 'immediate' || exit
    bashlog_queue_flush Auto --to STDOUT
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = $'level=info msg="immediate"\nlevel=info msg="queued"' ]
  [ -z "${stderr}" ]
}

@test "queued protected records are redacted before enqueueing and survive context destruction" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_redaction_add secrets fixed VeryPrivate '[R]' || exit
    bashlog_error --context secrets --to queue:Protected --tag auth 'token=%s' VeryPrivate || exit
    bashlog_redaction_context_destroy secrets || exit
    bashlog_queue_flush Protected --to STDOUT
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'error [auth]: token=[R]' ]
  [[ "${output}" != *VeryPrivate* ]]
  [[ "${stderr}" != *VeryPrivate* ]]
}

@test "additional context rules after enqueue do not retroactively alter queued bytes" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_redaction_add secrets fixed initial REDACTED || exit
    bashlog_info --context secrets --to queue:Older 'first=%s later=%s' initial later || exit
    bashlog_redaction_add secrets fixed later '[NEW]' || exit
    bashlog_queue_flush Older --to STDOUT
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'info: first=REDACTED later=later' ]
  [ -z "${stderr}" ]
}

@test "final verification failure suppresses record and queue remains empty" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add secrets fixed alpha '[A]' || exit
    bashlog_redaction_add secrets fixed beta alpha || exit
    bashlog_info --context secrets --to queue:Protected '%s' beta && exit 1
    [[ $? -eq 70 ]] || exit 2
    bashlog_queue_flush Protected --to STDOUT
BASH
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'bashlog: message suppressed' ]
  [[ "${stderr}" != *alpha* ]]
  [[ "${stderr}" != *beta* ]]
}

@test "redaction failure diagnostic stays on stderr for explicit STDOUT" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add ctx fixed alpha '[A]' || exit
    bashlog_redaction_add ctx fixed beta alpha || exit
    bashlog_info --context ctx --to STDOUT '%s' beta
BASH
  [ "${status}" -eq 70 ]
  [ -z "${output}" ]
  [ "${stderr}" = 'bashlog: message suppressed' ]
}

@test "queued timestamp belongs to enqueue event and remains fixed" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_timestamp_set utc || exit
    bashlog_info --to queue:Time 'clock' || exit
    bashlog_timestamp_set off || exit
    bashlog_queue_flush Time --to STDOUT
BASH
  [ "${status}" -eq 0 ]
  [[ "${output}" == ts=????-??-??T??:??:??Z\ level=info\ msg=\"clock\" ]]
  [ -z "${stderr}" ]
}

@test "queued bytes include one exact trailing newline per completed record" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:Lines one || exit
    bashlog_info --to queue:Lines two || exit
    bashlog_queue_flush Lines --to STDOUT
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = $'info: one\ninfo: two' ]
  [ -z "${stderr}" ]
}

@test "queue state in a subshell does not modify its parent" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:Parent 'parent' || exit
    ( bashlog_info --to queue:Parent 'child' ) || exit
    bashlog_queue_flush Parent --to STDOUT
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'info: parent' ]
  [ -z "${stderr}" ]
}

@test "queue routing and flushing work with no command-resolving PATH" {
  run_bashlog_script <<'BASH'
    PATH=/definitely/not/a/real/path
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:Plain '%s' value || exit
    bashlog_queue_flush Plain --to STDOUT
BASH
  [ "${status}" -eq 0 ]
  [ "${output}" = 'info: value' ]
  [ -z "${stderr}" ]
}
