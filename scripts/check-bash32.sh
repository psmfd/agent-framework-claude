#!/usr/bin/env bash
#
# scripts/check-bash32.sh — verify the bash 3.2 compatibility floor.
#
# setup.sh, hooks/*.sh, and scripts/lib/*.sh must run on macOS system bash
# (3.2.57). This script locates a genuine bash 3.2 binary and executes the
# 3.2-targeted surfaces under it: the shared-lib self-tests, syntax checks,
# hook smoke invocations, and the 3.2-safe test suites. CI runs it on a
# macOS runner (real /bin/bash 3.2); on hosts without a 3.2 binary it SKIPs
# rather than failing — the constraint is only checkable where 3.2 exists.
# See ADR-083.
#
# Usage:
#   scripts/check-bash32.sh
#
# Environment:
#   BASH32=<path>   explicit bash binary to use (must report major version 3)
#
# Exit codes:
#   0 — all checks passed (or skipped: no 3.2 binary available)
#   1 — one or more checks failed under bash 3.2
#   2 — environment/precondition failure
#
# This script itself is bash 3.2-safe (it may be run BY the binary it tests).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"

# --- Locate a bash 3.x binary -------------------------------------------------
find_bash32() {
  # Explicit override first, then macOS system bash (Apple freezes it at 3.2).
  candidate=""
  for candidate in "${BASH32:-}" /bin/bash; do
    [ -n "$candidate" ] || continue
    [ -x "$candidate" ] || continue
    # shellcheck disable=SC2016  # expansion must happen in the child bash
    ver="$("$candidate" -c 'printf %s "${BASH_VERSINFO[0]}"' 2>/dev/null || true)"
    if [ "$ver" = "3" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

BASH32_BIN="$(find_bash32 || true)"
if [ -z "$BASH32_BIN" ]; then
  if [ -n "${BASH32:-}" ]; then
    fatal "env" "BASH32='$BASH32' is not an executable bash with major version 3" 2
  fi
  skip "bash32" "no bash 3.x binary found (macOS /bin/bash or BASH32=<path>) — floor not checkable on this host"
  info "CI covers this check on a macOS runner; see ADR-083."
  exit 0
fi
# shellcheck disable=SC2016  # expansion must happen in the child bash
info "using $BASH32_BIN ($("$BASH32_BIN" -c 'printf %s "$BASH_VERSION"'))"

# --- 1. Shared-lib self-tests under 3.2 ---------------------------------------
for lib in "$REPO_DIR"/scripts/lib/*.sh; do
  name="$(basename "$lib")"
  if "$BASH32_BIN" "$lib" --self-test >/dev/null 2>&1; then
    ok "selftest" "$name --self-test passed under bash 3.2"
  else
    err "selftest" "$name --self-test FAILED under bash 3.2"
  fi
done

# --- 2. Syntax checks (parse-time only; runtime is covered by 3 and 4) --------
for f in "$REPO_DIR"/setup.sh "$REPO_DIR"/scripts/rulesets.sh "$REPO_DIR"/hooks/*.sh; do
  name="${f#"$REPO_DIR"/}"
  if "$BASH32_BIN" -n "$f" 2>/dev/null; then
    ok "syntax" "$name parses under bash 3.2"
  else
    err "syntax" "$name FAILS to parse under bash 3.2"
  fi
done

# --- 3. Hook smoke invocations ------------------------------------------------
# Minimal well-formed inputs through the real entry points. These catch
# runtime-only 3.2 breaks (declare -A, ${var,,}, mapfile) that bash -n cannot.
# The PreToolUse hooks treat an unrecognized/absent tool as allow (exit 0).
smoke_hook() {
  hook="$1"; payload="$2"; expect="$3"; label="$4"
  rc=0
  printf '%s' "$payload" | "$BASH32_BIN" "$REPO_DIR/hooks/$hook" >/dev/null 2>&1 || rc=$?
  if [ "$rc" = "$expect" ]; then
    ok "smoke" "$hook $label (exit $rc)"
  else
    err "smoke" "$hook $label — expected exit $expect, got $rc under bash 3.2"
  fi
}

smoke_hook session-secrets-guard.sh     '{"tool_name":"Read","tool_input":{}}' 0 "non-matching tool allowed"
smoke_hook session-gh-identity-guard.sh '{"tool_name":"Write","tool_input":{}}' 0 "non-matching tool allowed"
smoke_hook bash-destructive-guard.sh    '{"tool_name":"Write","tool_input":{}}' 0 "non-matching tool allowed"
smoke_hook stop-preflight-check.sh      '{}' 0 "empty payload allowed"
smoke_hook fanout-nudge.sh              '{"tool_calls":[]}' 0 "empty batch allowed"
smoke_hook subagent-verdict-guard.sh    '{}' 0 "empty payload allowed"
smoke_hook instructions-loaded-log.sh   '{}' 0 "empty payload allowed"

# gh-identity-guard.sh (pre-push contract): non-github remote passes silently.
rc=0
printf '' | "$BASH32_BIN" "$REPO_DIR/hooks/gh-identity-guard.sh" origin \
  "git@gitlab.example.com:owner/repo.git" >/dev/null 2>&1 || rc=$?
if [ "$rc" = "0" ]; then
  ok "smoke" "gh-identity-guard.sh non-github remote passes (exit 0)"
else
  err "smoke" "gh-identity-guard.sh non-github remote — expected exit 0, got $rc under bash 3.2"
fi

# --- 4. 3.2-safe test suites under 3.2 ----------------------------------------
# tests/validate/ is deliberately excluded: it drives validate.sh, which
# requires bash 4.0+ by design (see its header).
for suite in secrets-guard worktree-guard gh-identity-guard \
             session-gh-identity-guard session-secrets-guard \
             bash-destructive-guard rulesets fanout-nudge subagent-verdict-guard \
             instructions-loaded-log; do
  runner="$REPO_DIR/tests/$suite/run-tests.sh"
  if [ ! -f "$runner" ]; then
    skip "suite" "tests/$suite/run-tests.sh not found"
    continue
  fi
  if "$BASH32_BIN" "$runner" >/dev/null 2>&1; then
    ok "suite" "tests/$suite passed under bash 3.2"
  else
    err "suite" "tests/$suite FAILED under bash 3.2 — run '$BASH32_BIN tests/$suite/run-tests.sh' for detail"
  fi
done

print_summary
