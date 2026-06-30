#!/usr/bin/env bash
#
# scripts/lib/log.sh — shared output helpers for framework scripts.
#
# Source this file to get the canonical output helpers defined in
# rules/script-output-conventions.md, plus fatal() and print_summary().
#
#   . "$(dirname "$0")/../lib/log.sh"   # adjust the relative path per caller
#
# Helpers (rules/script-output-conventions.md):
#   ok    NAME MSG   — "OK    [NAME] MSG"   to stdout
#   skip  NAME MSG   — "SKIP  [NAME] MSG"   to stdout
#   warn  NAME MSG   — "WARN  [NAME] MSG"   to stderr; increments LOG_WARN_COUNT
#   info  MSG...     — "INFO  MSG"          to stdout
#   err   NAME MSG   — "ERROR [NAME] MSG"   to stderr; increments LOG_ERROR_COUNT
#   detail MSG...    — "      MSG"          to stdout, only when VERBOSE=1
#   fatal NAME MSG [CODE] — err() then exit CODE (default 1)
#   print_summary    — "===" rule + PASS/FAIL line; returns 1 if errors > 0
#
# Counters are owned here (like scripts/wim/_lib.sh): warn()/err() increment
# LOG_WARN_COUNT/LOG_ERROR_COUNT, and print_summary reads them. A caller that
# tracks its own counts can ignore these and pass nothing.
#
# Verbosity: detail() prints only when VERBOSE=1. Colour is opt-in via
# LOG_COLOR=1 and is emitted only to a tty; NO_COLOR (https://no-color.org)
# disables it unconditionally.
#
# Portability: this file is POSIX/bash-3.2 safe so callers on macOS system
# bash (e.g. setup.sh, scripts/setup-repo.sh) can source it. It does NOT set
# -euo pipefail — the caller owns shell options (see scripts/wim/_lib.sh).
#
# Run `bash scripts/lib/log.sh --self-test` to exercise the assertions
# (validate.sh check_lib_selftests runs this). All self-test output is on
# stderr so a caller capturing stdout is unaffected.

# --- Source guard (idempotent include) ---
[ "${_LIB_LOG_SH_LOADED:-}" = "1" ] && return 0
_LIB_LOG_SH_LOADED=1

# --- Counters (caller may inspect; print_summary consumes them) ---
: "${LOG_ERROR_COUNT:=0}"
: "${LOG_WARN_COUNT:=0}"

# --- Colour guard (opt-in; tty-only; NO_COLOR honoured) ---
_LOG_C_RESET="" _LOG_C_GREEN="" _LOG_C_YELLOW="" _LOG_C_RED=""
if [ "${LOG_COLOR:-0}" = "1" ] && [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
  if command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
    _LOG_C_RESET="$(tput sgr0)"
    _LOG_C_GREEN="$(tput setaf 2)"
    _LOG_C_YELLOW="$(tput setaf 3)"
    _LOG_C_RED="$(tput setaf 1)"
  fi
fi

# --- Output helpers ---
ok()   { printf '%sOK%s    [%s] %s\n'   "$_LOG_C_GREEN"  "$_LOG_C_RESET" "$1" "$2"; }
skip() { printf 'SKIP  [%s] %s\n'       "$1" "$2"; }
info() { printf 'INFO  %s\n'            "$*"; }

warn() {
  printf '%sWARN%s  [%s] %s\n' "$_LOG_C_YELLOW" "$_LOG_C_RESET" "$1" "$2" >&2
  LOG_WARN_COUNT=$(( LOG_WARN_COUNT + 1 ))
}

err() {
  printf '%sERROR%s [%s] %s\n' "$_LOG_C_RED" "$_LOG_C_RESET" "$1" "$2" >&2
  LOG_ERROR_COUNT=$(( LOG_ERROR_COUNT + 1 ))
}

# Indented detail line; printed only when VERBOSE=1.
detail() {
  [ "${VERBOSE:-0}" = "1" ] && printf '      %s\n' "$*"
  return 0
}

# err() then exit. Third arg overrides the exit code (default 1).
fatal() {
  err "$1" "$2"
  exit "${3:-1}"
}

# Print the summary block and return 1 if any errors were counted.
print_summary() {
  printf '==================================\n'
  if [ "${LOG_ERROR_COUNT:-0}" -gt 0 ]; then
    printf 'FAIL — %d errors, %d warnings\n' "$LOG_ERROR_COUNT" "$LOG_WARN_COUNT"
    return 1
  fi
  printf 'PASS — %d errors, %d warnings\n' "$LOG_ERROR_COUNT" "$LOG_WARN_COUNT"
  return 0
}

# --- Self-test (runs only when executed directly, not when sourced) ---
_log_self_test() {
  # All diagnostics to stderr; stdout stays clean for callers that capture it.
  local fails=0 got
  _assert() { # label want got
    if [ "$2" = "$3" ]; then
      printf 'ok   %s\n' "$1" >&2
    else
      printf 'FAIL %s\n      want: [%s]\n      got:  [%s]\n' "$1" "$2" "$3" >&2
      fails=$(( fails + 1 ))
    fi
  }

  # Colour off in a non-tty self-test run, so formats are exact.
  got="$(ok demo "all good")"
  _assert "ok-format"   "OK    [demo] all good" "$got"
  got="$(skip demo "n/a")"
  _assert "skip-format" "SKIP  [demo] n/a" "$got"
  got="$(info "hello world")"
  _assert "info-format" "INFO  hello world" "$got"

  # warn/err: STDERR carries the line (stdout empty); counters increment when
  # called directly (a subshell capture would discard the increment).
  got="$(warn demo "careful" 2>&1 >/dev/null)"
  _assert "warn-stderr"       "WARN  [demo] careful" "$got"
  got="$(warn demo "careful" 2>/dev/null)"
  _assert "warn-stdout-empty" "" "$got"
  LOG_WARN_COUNT=0; warn demo "careful" 2>/dev/null
  _assert "warn-counter"      "1" "$LOG_WARN_COUNT"

  got="$(err demo "broken" 2>&1 >/dev/null)"
  _assert "err-stderr"        "ERROR [demo] broken" "$got"
  got="$(err demo "broken" 2>/dev/null)"
  _assert "err-stdout-empty"  "" "$got"
  LOG_ERROR_COUNT=0; err demo "broken" 2>/dev/null
  _assert "err-counter"       "1" "$LOG_ERROR_COUNT"

  # detail() gated by VERBOSE.
  got="$(VERBOSE=0 detail "quiet")"
  _assert "detail-off" "" "$got"
  got="$(VERBOSE=1 detail "loud")"
  _assert "detail-on" "      loud" "$got"

  # print_summary: PASS at zero errors, FAIL otherwise (and rc reflects it).
  LOG_ERROR_COUNT=0 LOG_WARN_COUNT=2
  got="$(print_summary | tail -n1)"
  _assert "summary-pass" "PASS — 0 errors, 2 warnings" "$got"
  LOG_ERROR_COUNT=3 LOG_WARN_COUNT=1
  if print_summary >/dev/null; then _assert "summary-fail-rc" "1" "0"; else _assert "summary-fail-rc" "1" "1"; fi

  if [ "$fails" -gt 0 ]; then
    printf 'FAIL — log.sh self-test: %d assertion(s) failed\n' "$fails" >&2
    return 1
  fi
  printf 'PASS — log.sh self-test\n' >&2
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    --self-test) _log_self_test; exit $? ;;
    *) printf 'usage: %s --self-test\n' "$0" >&2; exit 2 ;;
  esac
fi
