#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  : "$BASHLOG_ARTIFACT"
}

run_bashlog_script() {
  run --separate-stderr bash --noprofile --norc -s -- "$BASHLOG_ARTIFACT" "$@"
}

@test "extraction preserves embedded newlines and every trailing newline" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:Exact '%s' $'first\n\n' || exit
    bashlog_warning --to queue:Exact second || exit
    bashlog_queue_extract Exact buffer || exit
    [[ $buffer == $'info: first\n\n\nwarning: second\n' ]] || exit 21
    bashlog_queue_flush Exact
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "new scalar receives records and drains the source queue" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:New hello || exit
    bashlog_queue_extract New buffer || exit
    [[ $buffer == $'info: hello\n' ]] || exit 21
    bashlog_queue_flush New --to STDOUT
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "existing scalar is replaced and empty queues assign an empty value" {
  run_bashlog_script <<'BASH'
    source "$1"
    buffer=old
    bashlog_info --to queue:Existing message || exit
    bashlog_queue_extract Existing buffer || exit
    [[ $buffer == $'level=info msg="message"\n' ]] || exit 21
    bashlog_queue_extract Missing buffer || exit
    [[ -z $buffer ]] || exit 22
    bashlog_queue_extract Missing other || exit
    [[ -z $other ]]
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "extracting one case-sensitive queue leaves the other untouched" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:Alpha upper || exit
    bashlog_info --to queue:alpha lower || exit
    bashlog_queue_extract Alpha buffer || exit
    [[ $buffer == $'info: upper\n' ]] || exit 21
    bashlog_queue_flush alpha --to STDOUT
BASH
  [ "$status" -eq 0 ]
  [ "$output" = 'info: lower' ]
  [ -z "$stderr" ]
}

@test "invalid queue names and argument counts preserve content" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:Good saved || exit
    for name in '' Bad_Name queue:Good Bad-name 'Bad Name'; do
      bashlog_queue_extract "$name" buffer && exit 21
      [[ $? -eq 64 ]] || exit 22
    done
    bashlog_queue_extract && exit 23
    [[ $? -eq 64 ]] || exit 24
    bashlog_queue_extract Good && exit 25
    [[ $? -eq 64 ]] || exit 26
    bashlog_queue_extract Good buffer extra && exit 27
    [[ $? -eq 64 ]] || exit 28
    bashlog_queue_flush Good --to STDOUT
BASH
  [ "$status" -eq 0 ]
  [ "$output" = 'info: saved' ]
  [ -z "$stderr" ]
}

@test "unsafe variable identifiers cannot execute shell expressions" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:Safe saved || exit
    for target in '' 'array[0]' 'bad name' 'a-b' 'x[$(printf injected >&2)]' $'new\nline'; do
      bashlog_queue_extract Safe "$target" && exit 21
      [[ $? -eq 64 ]] || exit 22
    done
    bashlog_queue_flush Safe --to STDOUT
BASH
  [ "$status" -eq 0 ]
  [ "$output" = 'info: saved' ]
  [ -z "$stderr" ]
}

@test "reserved Bash variables and internal logger state are protected" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:Guard saved || exit
    for target in IFS PATH RANDOM SECONDS LINENO BASH_VERSION BASH_REMATCH FUNCNAME PIPESTATUS BASHLOG_VERSION __bashlog_queue_records _; do
      bashlog_queue_extract Guard "$target" && exit 21
      [[ $? -eq 64 ]] || exit 22
    done
    bashlog_queue_flush Guard --to STDOUT
BASH
  [ "$status" -eq 0 ]
  [ "$output" = 'info: saved' ]
  [ -z "$stderr" ]
}

@test "readonly assignment fails without changing the queue or target" {
  run_bashlog_script <<'BASH'
    source "$1"
    readonly locked=old
    bashlog_info --to queue:Retain saved || exit
    bashlog_queue_extract Retain locked && exit 21
    [[ $? -eq 64 ]] || exit 22
    [[ $locked == old ]] || exit 23
    bashlog_queue_flush Retain --to STDOUT
BASH
  [ "$status" -eq 0 ]
  [ "$output" = 'level=info msg="saved"' ]
  [ -z "$stderr" ]
}

@test "integer, array, nameref, and exported targets are rejected" {
  run_bashlog_script <<'BASH'
    source "$1"
    declare -i numeric=7
    declare -a indexed=(first)
    declare -A associative=([a]=first)
    outside=original
    declare -n reference=outside
    export exported_buffer=old
    bashlog_info --to queue:Attributes '1+2' || exit
    for target in numeric indexed associative reference exported_buffer; do
      bashlog_queue_extract Attributes "$target" && exit 21
      [[ $? -eq 64 ]] || exit 22
    done
    [[ $numeric == 7 && $outside == original && $exported_buffer == old ]] || exit 23
    [[ ${indexed[0]} == first && ${associative[a]} == first ]] || exit 24
    bashlog_queue_flush Attributes --to STDOUT
BASH
  [ "$status" -eq 0 ]
  [ "$output" = 'level=info msg="1+2"' ]
  [ -z "$stderr" ]
}

@test "function-local scalar receives extracted bytes without global assignment" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:Local saved || exit
    consume() {
      local buffer=old
      bashlog_queue_extract Local buffer || return
      [[ $buffer == $'info: saved\n' ]]
    }
    consume || exit
    [[ ! -v buffer ]] || exit 21
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "subshell extraction does not drain parent queue" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:Parent saved || exit
    ( bashlog_queue_extract Parent child ) || exit
    bashlog_queue_flush Parent --to STDOUT
BASH
  [ "$status" -eq 0 ]
  [ "$output" = 'info: saved' ]
  [ -z "$stderr" ]
}

@test "redacted records survive context destruction and later rule changes" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_redaction_add secrets fixed private '[R]' || exit
    bashlog_warning --context secrets --to queue:Redacted '%s' private || exit
    bashlog_redaction_context_destroy secrets || exit
    bashlog_queue_extract Redacted data || exit
    [[ $data == $'warning: [R]\n' ]] || exit 21
    [[ $data != *private* ]] || exit 22
    bashlog_redaction_add newer fixed one '[ONE]' || exit
    bashlog_info --context newer --to queue:Past 'one/%s' later || exit
    bashlog_redaction_add newer fixed later '[LATER]' || exit
    bashlog_queue_extract Past data || exit
    [[ $data == $'info: [ONE]/later\n' ]]
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "extraction remains pure Bash when PATH cannot resolve commands" {
  run_bashlog_script <<'BASH'
    PATH=/definitely/not/a/real/path
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info --to queue:Offline saved || exit
    bashlog_queue_extract Offline data || exit
    [[ $data == $'info: saved\n' ]]
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}
