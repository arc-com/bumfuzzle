#!/usr/bin/env bash
# logging.sh — the sole source of printed output for every script in the
# `bf run` and `bf init` families. Every Plain, Banner, and Section
# instance, and any script's raw stdout return value/data, is emitted by
# calling one of the functions below — no other script in these families
# ever calls a print primitive (printf, echo, cat) directly.
#
# Meant to be sourced, not executed. Flags are consumed once, as
# positional arguments to the source statement that loads this file, and
# captured here — never re-read by the caller's own argument parsing,
# never re-supplied to individual log_*/log_banner/log_section calls
# below. Caller must set SCRIPT_NAME before sourcing.
set -euo pipefail

VERBOSE=false
PRETTIFY=false
PLAIN=false
for _logging_arg in "$@"; do
  case "$_logging_arg" in
    --verbose) VERBOSE=true ;;
    --prettify) PRETTIFY=true ;;
    --plain) PLAIN=true ;;
  esac
done

# log_quiet — true when narration should be suppressed: --plain without
# --verbose. A caller elsewhere in these families uses this to also gate
# its own supplementary output (e.g. a failure's details block) the same
# way log_debug/log_info/log_warn/log_error already gate themselves.
log_quiet() { [[ "$PLAIN" == true && "$VERBOSE" != true ]]; }

# log_debug/log_info/log_warn/log_error MESSAGE — Plain line to stderr:
# "[YY-MM-DDTHH:mm:ssZ][SCRIPT_NAME][LEVEL] - MESSAGE". DEBUG hidden
# unless --verbose was passed at source time. All four suppressed when
# --plain was passed without --verbose.
_log_line() {
  local _level="$1" _msg="$2"
  [[ "$_level" == "DEBUG" && "$VERBOSE" != true ]] && return 0
  log_quiet && return 0
  printf '[%s][%s][%s] - %s\n' "$(date -u +'%y-%m-%dT%H:%M:%SZ')" "$SCRIPT_NAME" "$_level" "$_msg" >&2
}
log_debug() { _log_line DEBUG "$1"; }
log_info()  { _log_line INFO  "$1"; }
log_warn()  { _log_line WARN  "$1"; }
log_error() { _log_line ERROR "$1"; }

# log_data FORMAT [ARGS...] — a script's actual return value or other
# stdout data (a [PASS]/[FAIL] finding, a resolved path, a --plain
# verdict, etc.): forwards straight to printf, always to stdout, never
# gated by any flag here. This is Plain's stdout carve-out ("stdout is
# reserved exclusively for a script's actual return value or data"), not
# a log line.
log_data() { printf "$@"; }

# log_banner_delim — a single Banner delimiter line to stdout. Entirely a
# no-op unless --prettify was passed at source time. Exposed separately
# from log_banner for a caller whose content between the two delimiters
# isn't itself prettify-gated (e.g. a failure list that must always print
# per the failure-diagnostics-always-visible rule) — such a caller emits
# that content through log_data, never through this or log_banner, and
# calls this once on either side of it instead.
log_banner_delim() {
  [[ "$PRETTIFY" == true ]] || return 0
  printf '%s\n' "$(printf '%*s' 71 '' | tr ' ' '-')"
}

# log_banner LINE... — Banner block: opening delimiter, each LINE,
# closing delimiter, all to stdout. Entirely a no-op unless --prettify
# was passed at source time. Only fit for content that is itself entirely
# conditional on --prettify (see log_banner_delim otherwise).
log_banner() {
  [[ "$PRETTIFY" == true ]] || return 0
  local _delim; _delim="$(printf '%*s' 71 '' | tr ' ' '-')"
  printf '%s\n' "$_delim"
  printf '%s\n' "$@"
  printf '%s\n' "$_delim"
}

# log_section LABEL — Section header to stdout: "-- Label " + '-' fill to
# a fixed 73-column total width, extending past 73 rather than truncating
# LABEL if fill would drop below 2 characters. Entirely a no-op unless
# --prettify was passed at source time.
log_section() {
  [[ "$PRETTIFY" == true ]] || return 0
  local _label="$1"
  local _prefix="-- $_label "
  local _fill=$(( 73 - ${#_prefix} ))
  [[ "$_fill" -lt 2 ]] && _fill=2
  printf '\n%s%s\n' "$_prefix" "$(printf '%*s' "$_fill" '' | tr ' ' '-')"
}

# log_section_pending LABEL / log_section_flush — lazy variant of
# log_section, for a caller that knows a grouping's label in advance but
# not yet whether anything will be logged beneath it. log_section_pending
# records LABEL without printing; log_section_flush prints it (still
# gated by --prettify) the first time it's called after a pending label
# was recorded, then clears it so it never double-prints. If
# log_section_flush is never called, the header never appears — an empty
# grouping produces no output.
_LOG_PENDING_SECTION=""
log_section_pending() { _LOG_PENDING_SECTION="$1"; }
log_section_flush() {
  [[ -n "$_LOG_PENDING_SECTION" ]] || return 0
  log_section "$_LOG_PENDING_SECTION"
  _LOG_PENDING_SECTION=""
}
