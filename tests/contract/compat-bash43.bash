#!/usr/bin/env bash

set -u

: "${BASHLOG_ARTIFACT:?BASHLOG_ARTIFACT must identify the artifact under test}"

source "${BASHLOG_ARTIFACT}"

[[ $(bashlog_level_get) == info ]] || exit 1
[[ $(bashlog_format_get) == auto ]] || exit 1
[[ $(bashlog_timestamp_get) == off ]] || exit 1
[[ $(bashlog_color_get) == auto ]] || exit 1

bashlog_level_set debug || exit 1
bashlog_format_set human || exit 1
bashlog_color_set never || exit 1

stdout_file="${TMPDIR:-/tmp}/bashlog-compat-stdout.$$"
stderr_file="${TMPDIR:-/tmp}/bashlog-compat-stderr.$$"
trap 'rm -f "${stdout_file}" "${stderr_file}"' EXIT

bashlog_info 'compatibility=%s' bash43 >"${stdout_file}" 2>"${stderr_file}" || exit 1
[[ ! -s ${stdout_file} ]] || exit 1
[[ $(<"${stderr_file}") == 'info: compatibility=bash43' ]] || exit 1

bashlog_format_set logfmt || exit 1
bashlog_info --tag compat 'compatibility=%s' bash43 >"${stdout_file}" 2>"${stderr_file}" || exit 1
[[ ! -s ${stdout_file} ]] || exit 1
[[ $(<"${stderr_file}") == 'level=info tag=compat msg="compatibility=bash43"' ]] || exit 1

bashlog_timestamp_set utc || exit 1
bashlog_info 'timestamp-check' >"${stdout_file}" 2>"${stderr_file}" || exit 1
[[ ! -s ${stdout_file} ]] || exit 1
[[ $(<"${stderr_file}") =~ ^ts=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\ level=info\ msg="timestamp-check"$ ]] || exit 1
bashlog_timestamp_set off || exit 1
bashlog_format_set human || exit 1

bashlog_redaction_add auth fixed 'secret' '[R]' || exit 1
[[ $(bashlog_redact auth 'value=secret') == 'value=[R]' ]] || exit 1

bashlog_info --context auth 'value=%s' secret >"${stdout_file}" 2>"${stderr_file}" || exit 1
[[ ! -s ${stdout_file} ]] || exit 1
[[ $(<"${stderr_file}") == 'info: value=[R]' ]] || exit 1

bashlog_redaction_add auth glob 'token-???' '[TOKEN]' || exit 1
[[ $(bashlog_redact auth 'token-abc') == '[TOKEN]' ]] || exit 1

bashlog_redaction_add auth ere '[0-9]{3}-[0-9]{2}-[0-9]{4}' '[SSN]' || exit 1
[[ $(bashlog_redact auth '123-45-6789') == '[SSN]' ]] || exit 1

bashlog_redaction_context_destroy auth || exit 1
bashlog_redact auth 'secret' >"${stdout_file}" 2>"${stderr_file}"
[[ $? -eq 69 ]] || exit 1
[[ ! -s ${stdout_file} ]] || exit 1

bashlog_redaction_add verify fixed alpha '[A]' || exit 1
bashlog_redaction_add verify fixed beta alpha || exit 1
bashlog_redact verify beta >"${stdout_file}" 2>"${stderr_file}"
[[ $? -eq 70 ]] || exit 1
[[ ! -s ${stdout_file} ]] || exit 1
[[ $(<"${stderr_file}") == 'bashlog: message suppressed' ]] || exit 1

exit 0
