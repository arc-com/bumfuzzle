#!/usr/bin/env bash
# lib.sh — shared non-logging helpers (timing, hashing) for the bf run and
# bf init script families. Meant to be sourced, not executed directly. All
# logging/output for these families goes through scripts/logging.sh
# instead — this file carries none of it, to keep the two concerns split
# by single responsibility.
set -euo pipefail

# millisecond-precision wall clock via `date +%s%N` (falls back to
# whole-second precision via bash's SECONDS builtin on a `date` without %N
# support). Precision is probed once, here, at source time. _now_ms() itself
# must never print anything but the numeric value, since its stdout is
# captured as the return value by every caller.
_ns_probe=$(date +%s%N 2>/dev/null || true)
if [[ "$_ns_probe" =~ ^[0-9]+$ ]]; then
  _HAS_NS_PRECISION=true
else
  _HAS_NS_PRECISION=false
fi

_now_ms() {
  if [[ "$_HAS_NS_PRECISION" == true ]]; then
    printf '%s' "$(( $(date +%s%N) / 1000000 ))"
  else
    printf '%s' "$(( SECONDS * 1000 ))"
  fi
}

# _sha256 FILE... — sha256sum where available, shasum otherwise (macOS
# ships shasum, not sha256sum, by default). Shared here rather than
# reimplemented per caller; scripts/release/lib.sh's tarball_sha256 is a
# different, narrower job (download-then-hash a tarball) and is left as is.
_sha256() { command -v sha256sum >/dev/null 2>&1 && sha256sum "$@" || shasum -a 256 "$@"; }
