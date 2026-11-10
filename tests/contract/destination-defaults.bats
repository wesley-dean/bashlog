#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  : "$BASHLOG_ARTIFACT"
}

run_bashlog_script() {
  run --separate-stderr bash --noprofile --norc -s -- "$BASHLOG_ARTIFACT" "$@"
}

@test "initial global default is STDERR and getter writes exactly one line" {
  run_bashlog_script <<'BASH'
    source "$1"
    [[ $(bashlog_destination_get) == STDERR ]] || exit 21
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_info 'ordinary'
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$stderr" = 'info: ordinary' ]
}

@test "global STDOUT default routes ordinary calls to stdout" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_destination_set --to STDOUT || exit
    [[ $(bashlog_destination_get) == STDOUT ]] || exit 21
    bashlog_warning 'routed'
BASH
  [ "$status" -eq 0 ]
  [ "$output" = 'warning: routed' ]
  [ -z "$stderr" ]
}

@test "global queue default buffers, and flush still uses stderr by default" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_destination_set --to queue:Pending || exit
    bashlog_info 'one' || exit
    bashlog_warning 'two' || exit
    bashlog_queue_flush Pending
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$stderr" = $'info: one\nwarning: two' ]
}

@test "global reset restores stderr without touching queued records" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_destination_set --to queue:Kept || exit
    bashlog_info 'older' || exit
    bashlog_destination_reset || exit
    [[ $(bashlog_destination_get) == STDERR ]] || exit 21
    bashlog_error 'newer' || exit
    bashlog_queue_flush Kept
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$stderr" = $'error: newer\ninfo: older' ]
}

@test "context destination set requires a preexisting active redaction context" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_destination_set --context absent --to STDOUT && exit 21
    [[ $? -eq 69 ]] || exit 22
    bashlog_destination_get --context absent && exit 23
    [[ $? -eq 69 ]] || exit 24
    bashlog_destination_reset --context absent && exit 25
    [[ $? -eq 69 ]] || exit 26
    [[ $(bashlog_destination_get) == STDERR ]]
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "context override applies only when --context is selected" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_redaction_add auth fixed private '[R]' || exit
    bashlog_destination_set --context auth --to STDOUT || exit
    bashlog_info 'not-context' || exit
    bashlog_info --context auth 'protected=%s' private
BASH
  [ "$status" -eq 0 ]
  [ "$output" = 'info: protected=[R]' ]
  [ "$stderr" = 'info: not-context' ]
}

@test "context getter inherits global default when no override is set" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add auth fixed secret '[R]' || exit
    [[ $(bashlog_destination_get --context auth) == STDERR ]] || exit 21
    bashlog_destination_set --to queue:Global || exit
    [[ $(bashlog_destination_get --context auth) == queue:Global ]] || exit 22
    bashlog_destination_set --to STDOUT || exit
    [[ $(bashlog_destination_get --context auth) == STDOUT ]]
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "explicit context stderr override survives global default changes" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_destination_set --context auth --to STDERR || exit
    bashlog_destination_set --to STDOUT || exit
    [[ $(bashlog_destination_get --context auth) == STDERR ]] || exit 21
    bashlog_warning --context auth 'keeps-stderr'
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$stderr" = 'warning: keeps-stderr' ]
}

@test "explicit per-call destination outranks context override and global default" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_destination_set --to queue:Global || exit
    bashlog_destination_set --context auth --to queue:Context || exit
    bashlog_info --context auth --to STDOUT 'secret=%s' secret || exit
    bashlog_info --context auth 'second' || exit
    bashlog_info 'third' || exit
    bashlog_queue_flush Context --to STDERR || exit
    bashlog_queue_flush Global --to STDERR
BASH
  [ "$status" -eq 0 ]
  [ "$output" = 'info: secret=[R]' ]
  [ "$stderr" = $'info: second\ninfo: third' ]
}

@test "context reset removes override and restores global inheritance" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_destination_set --to queue:Global || exit
    bashlog_destination_set --context auth --to STDOUT || exit
    bashlog_destination_reset --context auth || exit
    [[ $(bashlog_destination_get --context auth) == queue:Global ]] || exit 21
    bashlog_info --context auth 'inherited' || exit
    bashlog_queue_flush Global --to STDERR
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$stderr" = 'info: inherited' ]
}

@test "context reset does not modify global default or other context overrides" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add one fixed secret '[R]' || exit
    bashlog_redaction_add two fixed secret '[R]' || exit
    bashlog_destination_set --to STDOUT || exit
    bashlog_destination_set --context one --to queue:One || exit
    bashlog_destination_set --context two --to queue:Two || exit
    bashlog_destination_reset --context one || exit
    [[ $(bashlog_destination_get) == STDOUT ]] || exit 21
    [[ $(bashlog_destination_get --context one) == STDOUT ]] || exit 22
    [[ $(bashlog_destination_get --context two) == queue:Two ]]
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "set option order works either way with strict syntax" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_destination_set --to STDOUT --context auth || exit
    [[ $(bashlog_destination_get --context auth) == STDOUT ]] || exit 21
    bashlog_destination_set --context auth --to queue:Errors || exit
    [[ $(bashlog_destination_get --context auth) == queue:Errors ]]
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "invalid destinations and duplicate flags do not mutate configuration" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_destination_set --to queue:Previous || exit
    bashlog_destination_set --context auth --to STDOUT || exit
    for destination in stderr stdout queue: queue:bad_name queue:bad-name file:path rsyslog:host:514 'queue:bad name'; do
      bashlog_destination_set --to "$destination" && exit 21
      [[ $? -eq 64 ]] || exit 22
    done
    bashlog_destination_set --to STDERR --to STDOUT && exit 23
    [[ $? -eq 64 ]] || exit 24
    bashlog_destination_set --context auth --context auth --to STDERR && exit 25
    [[ $? -eq 64 ]] || exit 26
    bashlog_destination_set --context auth --to STDOUT --unknown && exit 27
    [[ $? -eq 64 ]] || exit 28
    bashlog_destination_set --context auth --to queue:bad_name && exit 29
    [[ $? -eq 64 ]] || exit 30
    [[ $(bashlog_destination_get) == queue:Previous ]] || exit 31
    [[ $(bashlog_destination_get --context auth) == STDOUT ]]
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "invalid getter and reset shapes leave configuration unchanged" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_destination_set --to STDOUT || exit
    for op in get reset; do
      bashlog_destination_"$op" --context && exit 21
      [[ $? -eq 64 ]] || exit 22
      bashlog_destination_"$op" --to STDERR && exit 23
      [[ $? -eq 64 ]] || exit 24
      bashlog_destination_"$op" garbage && exit 25
      [[ $? -eq 64 ]] || exit 26
      bashlog_destination_"$op" --context bad_name! && exit 27
      [[ $? -eq 64 ]] || exit 28
    done
    [[ $(bashlog_destination_get) == STDOUT ]]
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "destroying a context clears its destination override but keeps queues" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_redaction_add auth fixed private '[R]' || exit
    bashlog_destination_set --context auth --to queue:Stored || exit
    bashlog_error --context auth '%s' private || exit
    bashlog_redaction_context_destroy auth || exit
    bashlog_destination_get --context auth && exit 21
    [[ $? -eq 69 ]] || exit 22
    bashlog_destination_reset --context auth && exit 23
    [[ $? -eq 69 ]] || exit 24
    bashlog_destination_set --context auth --to STDERR && exit 25
    [[ $? -eq 69 ]] || exit 26
    bashlog_queue_flush Stored --to STDOUT
BASH
  [ "$status" -eq 0 ]
  [ "$output" = 'error: [R]' ]
  [ -z "$stderr" ]
}

@test "context routing is still protected by fail-closed redaction checks" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add auth fixed alpha '[A]' || exit
    bashlog_redaction_add auth fixed beta alpha || exit
    bashlog_destination_set --context auth --to STDOUT || exit
    bashlog_error --context auth '%s' beta && exit 21
    [[ $? -eq 70 ]] || exit 22
    bashlog_destination_set --context auth --to queue:Failed || exit
    bashlog_error --context auth '%s' beta && exit 23
    [[ $? -eq 70 ]] || exit 24
    bashlog_queue_flush Failed --to STDOUT
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$stderr" = $'bashlog: message suppressed\nbashlog: message suppressed' ]
}

@test "threshold-suppressed records never enter configured destination" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_destination_set --to queue:Suppressed || exit
    bashlog_debug '%s' 'value' || exit
    bashlog_queue_flush Suppressed --to STDOUT
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "global defaults and context overrides survive independent queue operations" {
  run_bashlog_script <<'BASH'
    source "$1"
    bashlog_redaction_add auth fixed secret '[R]' || exit
    bashlog_destination_set --to queue:Global || exit
    bashlog_destination_set --context auth --to queue:Auth || exit
    bashlog_info 'first' || exit
    bashlog_queue_clear Global || exit
    bashlog_queue_extract Auth buffer || exit
    [[ -z $buffer ]] || exit 21
    [[ $(bashlog_destination_get) == queue:Global ]] || exit 22
    [[ $(bashlog_destination_get --context auth) == queue:Auth ]]
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "setting defaults remains pure Bash with an unusable PATH" {
  run_bashlog_script <<'BASH'
    PATH=/definitely/not/a/real/path
    source "$1"
    bashlog_format_set human || exit
    bashlog_color_set never || exit
    bashlog_destination_set --to queue:Offline || exit
    bashlog_info 'stored' || exit
    bashlog_queue_flush Offline --to STDOUT
BASH
  [ "$status" -eq 0 ]
  [ "$output" = 'info: stored' ]
  [ -z "$stderr" ]
}

@test "configuration changes in a subshell do not propagate to its parent" {
  run_bashlog_script <<'BASH'
    source "$1"
    ( bashlog_destination_set --to STDOUT ) || exit
    [[ $(bashlog_destination_get) == STDERR ]]
BASH
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}
