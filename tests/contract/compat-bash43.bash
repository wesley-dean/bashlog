#!/usr/bin/env bash

set -u

: "${BASHLOG_ARTIFACT:?BASHLOG_ARTIFACT must identify the artifact under test}"

fail() {
  printf 'bash43 compatibility failure: %s\n' "$1" >&2
  exit 1
}

source "${BASHLOG_ARTIFACT}"

[[ $(bashlog_level_get) == info ]] || fail 'default level'
[[ $(bashlog_format_get) == auto ]] || fail 'default format'
[[ $(bashlog_timestamp_get) == off ]] || fail 'default timestamp'
[[ $(bashlog_color_get) == auto ]] || fail 'default color'

bashlog_level_set debug || fail 'set debug threshold'
bashlog_format_set human || fail 'set human format'
bashlog_color_set never || fail 'set color never'

stdout_file="${TMPDIR:-/tmp}/bashlog-compat-stdout.$$"
stderr_file="${TMPDIR:-/tmp}/bashlog-compat-stderr.$$"
trap 'rm -f "${stdout_file}" "${stderr_file}"' EXIT

bashlog_info 'compatibility=%s' bash43 >"${stdout_file}" 2>"${stderr_file}" || fail 'human info call'
[[ ! -s ${stdout_file} ]] || fail 'human info stdout'
[[ $(<"${stderr_file}") == 'info: compatibility=bash43' ]] || fail 'human info rendering'

bashlog_format_set logfmt || fail 'set logfmt format'
bashlog_info --tag compat 'compatibility=%s' bash43 >"${stdout_file}" 2>"${stderr_file}" || fail 'logfmt info call'
[[ ! -s ${stdout_file} ]] || fail 'logfmt info stdout'
[[ $(<"${stderr_file}") == 'level=info tag=compat msg="compatibility=bash43"' ]] || fail 'logfmt rendering'

bashlog_timestamp_set utc || fail 'set UTC timestamp'
bashlog_info 'timestamp-check' >"${stdout_file}" 2>"${stderr_file}" || fail 'UTC timestamp log call'
[[ ! -s ${stdout_file} ]] || fail 'UTC timestamp stdout'
[[ $(<"${stderr_file}") =~ ^ts=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\ level=info\ msg="timestamp-check"$ ]] || fail 'UTC timestamp rendering'
bashlog_timestamp_set off || fail 'disable timestamp'
bashlog_format_set human || fail 'restore human format'

bashlog_redaction_add auth fixed 'secret' '[R]' || fail 'register fixed rule'
[[ $(bashlog_redact auth 'value=secret') == 'value=[R]' ]] || fail 'standalone fixed redaction'

bashlog_info --context auth 'value=%s' secret >"${stdout_file}" 2>"${stderr_file}" || fail 'logger-managed fixed redaction call'
[[ ! -s ${stdout_file} ]] || fail 'logger-managed fixed redaction stdout'
[[ $(<"${stderr_file}") == 'info: value=[R]' ]] || fail 'logger-managed fixed redaction rendering'

bashlog_redaction_add auth glob 'token-???' '[TOKEN]' || fail 'register glob rule'
[[ $(bashlog_redact auth 'token-abc') == '[TOKEN]' ]] || fail 'glob redaction'

bashlog_redaction_add auth ere '[0-9]{3}-[0-9]{2}-[0-9]{4}' '[SSN]' || fail 'register ERE rule'
[[ $(bashlog_redact auth '123-45-6789') == '[SSN]' ]] || fail 'ERE redaction'

bashlog_redaction_context_destroy auth || fail 'destroy context'
bashlog_redact auth 'secret' >"${stdout_file}" 2>"${stderr_file}"
[[ $? -eq 69 ]] || fail 'destroyed context status'
[[ ! -s ${stdout_file} ]] || fail 'destroyed context stdout'

bashlog_redaction_add verify fixed alpha '[A]' || fail 'register verification rule one'
bashlog_redaction_add verify fixed beta alpha || fail 'register verification rule two'
bashlog_redact verify beta >"${stdout_file}" 2>"${stderr_file}"
[[ $? -eq 70 ]] || fail 'cross-rule verification status'
[[ ! -s ${stdout_file} ]] || fail 'cross-rule verification stdout'
[[ $(<"${stderr_file}") == 'bashlog: message suppressed' ]] || fail 'cross-rule verification diagnostic'

exit 0
