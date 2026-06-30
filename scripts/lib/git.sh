#!/usr/bin/env bash
#
# scripts/lib/git.sh — shared git helpers for framework scripts.
#
# Source this file to get git introspection helpers:
#
#   . "$(dirname "$0")/../lib/git.sh"   # adjust the relative path per caller
#
# Helpers:
#   git_repo_root — print the repository top-level path to stdout; return 1
#                   (no output) when the working directory is not a git repo.
#                   The caller decides whether that condition is fatal.
#
# Portability: POSIX/bash-3.2 safe. Does NOT set -euo pipefail — the caller
# owns shell options (see scripts/wim/_lib.sh).
#
# Run `bash scripts/lib/git.sh --self-test` to exercise the assertions
# (validate.sh check_lib_selftests runs this). All self-test output is on
# stderr so a caller capturing stdout is unaffected.

# --- Source guard (idempotent include) ---
[ "${_LIB_GIT_SH_LOADED:-}" = "1" ] && return 0
_LIB_GIT_SH_LOADED=1

# Print the repo top-level to stdout; return 1 with no output when not in a repo.
git_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || return 1
}

# --- Self-test (runs only when executed directly, not when sourced) ---
_git_self_test() {
  local fails=0 got rc
  _assert() { # label want got
    if [ "$2" = "$3" ]; then
      printf 'ok   %s\n' "$1" >&2
    else
      printf 'FAIL %s\n      want: [%s]\n      got:  [%s]\n' "$1" "$2" "$3" >&2
      fails=$(( fails + 1 ))
    fi
  }

  # Positive: inside this repo, git_repo_root returns a directory containing .git.
  got="$(git_repo_root)"; rc=$?
  _assert "repo-root-rc" "0" "$rc"
  if [ -n "$got" ] && [ -d "$got/.git" ]; then
    _assert "repo-root-is-repo" "yes" "yes"
  else
    _assert "repo-root-is-repo" "yes" "no ($got)"
  fi
  # It must agree with git's own answer.
  _assert "repo-root-matches-git" "$(git rev-parse --show-toplevel 2>/dev/null)" "$got"

  # Negative: in a fresh non-repo temp dir, return 1 with empty stdout.
  local tmp
  tmp="$(mktemp -d 2>/dev/null)" || tmp=""
  if [ -n "$tmp" ]; then
    got="$(cd "$tmp" && git_repo_root)"; rc=$?
    _assert "non-repo-rc"     "1"  "$rc"
    _assert "non-repo-empty"  ""   "$got"
    rm -rf "$tmp"
  else
    printf 'ok   non-repo-skipped (mktemp unavailable)\n' >&2
  fi

  if [ "$fails" -gt 0 ]; then
    printf 'FAIL — git.sh self-test: %d assertion(s) failed\n' "$fails" >&2
    return 1
  fi
  printf 'PASS — git.sh self-test\n' >&2
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    --self-test) _git_self_test; exit $? ;;
    *) printf 'usage: %s --self-test\n' "$0" >&2; exit 2 ;;
  esac
fi
