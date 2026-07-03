#!/usr/bin/env bash
#
# run-tests.sh — acceptance tests for hooks/fanout-nudge.sh (the PostToolBatch
# fan-out advisory nudge, ADR-090; phase 2 of #24)
#
# Contract under test: stdin=JSON PostToolBatch payload with tool_calls[].
# ALWAYS exits 0. The only variable is whether a nudge is emitted:
#   - stdout: a hookSpecificOutput.additionalContext JSON payload when nudging,
#     otherwise silent.
#   - stderr: a `WARN  [fanout-nudge] ...` line alongside the nudge, or a
#     fail-open / skip WARN.
# Signal: n Agent/Task calls, ntypes distinct subagent_type, nprompts distinct
# prompts. No nudge when n==0, when n>=3 && ntypes>=3 (divergence), or when
# n>=3 && ntypes==1 && nprompts==1 (the replication shape). Otherwise a nudge.
# Matches BOTH "Agent" and "Task" tool names. Fail-open uniformly.
#
# Coverage:
#   1. 3 distinct subagent_types (Agent)          -> no nudge (divergence)
#   2. replication: 3x same type + same prompt    -> no nudge
#   3. batch of Read calls (0 agent calls)        -> no nudge (short-circuit)
#   4. tool_calls absent entirely                 -> no nudge (determinate 0)
#   5. 3 distinct types via the "Task" tool name  -> no nudge (both names count)
#   6. mixed 2 Agent + 1 Task, 3 distinct types   -> no nudge (mixed counting)
#   7. 1 agent call                               -> nudge
#   8. 2 agent calls, 2 distinct types            -> nudge (count < 3)
#   9. 3 calls, 2 distinct types (A,A,B)          -> nudge (weak angle signal)
#  10. 3 calls same type, different prompts       -> nudge (same agent != angles)
#  11. jq absent from PATH                        -> no nudge, fail-open WARN
#  12. empty stdin                                -> no nudge, silent
#  13. malformed JSON                             -> no nudge, fail-open
#  14. SKIP_FANOUT_NUDGE=1                         -> no nudge, skip WARN
#  15. concatenated multi-document stdin           -> no nudge (single-doc guard)
#  16. valid JSON, non-object tool_calls entry     -> no nudge (jq error, fail-open)
#
# Output per rules/script-output-conventions.md.
# Exit codes: 0 all pass, 1 one or more failures, 2 precondition failure.
# Targets bash 3.2+ (the hook's floor). Run: bash tests/fanout-nudge/run-tests.sh

# -e omitted: the runner must continue past a failing case to report all
# results; failures are tracked via the `errors` counter.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../../hooks/fanout-nudge.sh"

ok()   { echo "OK    [$1] $2"; }
err()  { echo "ERROR [$1] $2" >&2; }
info() { echo "INFO  $*"; }

errors=0
TMPFILES=()
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
cleanup() { local f; for f in ${TMPFILES[@]+"${TMPFILES[@]}"}; do [ -n "$f" ] && rm -rf "$f"; done; }
trap cleanup EXIT

for cmd in jq bash; do
  command -v "$cmd" >/dev/null 2>&1 || { err "env" "$cmd is required but not on PATH"; exit 2; }
done
[ -f "$HOOK" ] || { err "env" "hook not found at $HOOK"; exit 2; }

# Resolve the interpreter ONCE, before any case restricts PATH.
BASH_BIN="$(command -v bash)"

ERRFILE="$(mktemp)"
TMPFILES+=("$ERRFILE")
INFILE="$(mktemp)"
TMPFILES+=("$INFILE")

# Synthetic PATH lacking jq (same technique as the sibling suites — symlink the
# wanted tool set into a throwaway dir; deterministic across host layouts).
build_path_without_jq() {
  local dir c src
  dir="$(mktemp -d)"
  TMPFILES+=("$dir")
  for c in cat sed awk printf tr; do
    src="$(command -v "$c" 2>/dev/null)" || continue
    case "$src" in /*) ln -s "$src" "$dir/$c" ;; esac
  done
  printf '%s' "$dir"
}

# --- Payload builders --------------------------------------------------------
# mk_call TOOLNAME TYPE PROMPT -> one tool_calls[] entry
mk_call() {
  jq -nc --arg tn "$1" --arg t "$2" --arg p "$3" \
    '{tool_name: $tn, tool_input: {subagent_type: $t, prompt: $p}}'
}
# mk_batch CALLJSON...  -> a PostToolBatch payload wrapping the given entries
mk_batch() {
  printf '%s\n' "$@" | jq -sc '{hook_event_name: "PostToolBatch", tool_calls: .}'
}

# --- Runner ------------------------------------------------------------------
OUT="" ERR="" RC=0
run_hook() {
  local payload="$1" use_path="${2:-$PATH}"
  RC=0
  # Feed stdin via file redirection, never `printf | hook`: on skip paths the
  # hook exits before reading stdin, and under pipefail the printf side can
  # lose the pipe-close race (EPIPE) and poison the pipeline result — the
  # bash-3.2 CI failure diagnosed in PR #59 and hardened here per #60.
  printf '%s' "$payload" > "$INFILE"
  OUT="$(PATH="$use_path" "$BASH_BIN" "$HOOK" < "$INFILE" 2>"$ERRFILE")" || RC=$?
  ERR="$(cat "$ERRFILE")"
}

# --- Assertions --------------------------------------------------------------
assert_no_nudge() {
  local name="$1"
  if [ "$RC" = 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then
    ok "$name" "no nudge (exit 0, silent)"
  else
    err "$name" "expected silent no-nudge, got exit $RC stdout='$(printf '%s' "$OUT" | tr '\n' '|')' stderr='$(printf '%s' "$ERR" | tr '\n' '|')'"
    errors=$((errors + 1))
  fi
}

assert_nudge() {
  local name="$1"
  if [ "$RC" != 0 ]; then
    err "$name" "expected exit 0, got $RC"; errors=$((errors + 1)); return
  fi
  if ! printf '%s' "$OUT" | jq -e '.hookSpecificOutput.hookEventName == "PostToolBatch" and (.hookSpecificOutput.additionalContext | length > 0)' >/dev/null 2>&1; then
    err "$name" "stdout is not a valid nudge JSON payload — got '$(printf '%s' "$OUT" | tr '\n' '|')'"
    errors=$((errors + 1)); return
  fi
  case "$ERR" in
    *"WARN  [fanout-nudge]"*) ok "$name" "nudge emitted (JSON stdout + stderr WARN)" ;;
    *) err "$name" "nudge JSON present but stderr WARN missing — got '$(printf '%s' "$ERR" | tr '\n' '|')'"; errors=$((errors + 1)) ;;
  esac
}

# stdout must be empty (no nudge), stderr must contain substring (fail-open/skip)
assert_failopen() {
  local name="$1" substr="$2"
  if [ "$RC" != 0 ] || [ -n "$OUT" ]; then
    err "$name" "expected exit 0 with empty stdout, got exit $RC stdout='$(printf '%s' "$OUT" | tr '\n' '|')'"
    errors=$((errors + 1)); return
  fi
  case "$ERR" in
    *"$substr"*) ok "$name" "fail-open exit 0, no nudge (stderr: $substr)" ;;
    *) err "$name" "missing stderr substring '$substr' — got '$(printf '%s' "$ERR" | tr '\n' '|')'"; errors=$((errors + 1)) ;;
  esac
}

reset_case_env() { unset SKIP_FANOUT_NUDGE; }

# --- Case 1: 3 distinct subagent_types -> no nudge ---------------------------
case_divergence_no_nudge() {
  reset_case_env
  run_hook "$(mk_batch \
    "$(mk_call Agent shell-expert 'angle a')" \
    "$(mk_call Agent docs-expert 'angle b')" \
    "$(mk_call Agent code-review-expert 'angle c')")"
  assert_no_nudge "divergence-no-nudge"
}

# --- Case 2: replication (3x same type + same prompt) -> no nudge -------------
case_replication_no_nudge() {
  reset_case_env
  run_hook "$(mk_batch \
    "$(mk_call Agent security-review-expert 'identical prompt')" \
    "$(mk_call Agent security-review-expert 'identical prompt')" \
    "$(mk_call Agent security-review-expert 'identical prompt')")"
  assert_no_nudge "replication-no-nudge"
}

# --- Case 3: batch of Read calls (0 agent calls) -> no nudge -----------------
case_no_agent_calls_no_nudge() {
  reset_case_env
  run_hook "$(mk_batch \
    "$(mk_call Read '' '')" \
    "$(mk_call Bash '' '')")"
  assert_no_nudge "no-agent-calls-no-nudge"
}

# --- Case 4: tool_calls absent entirely -> no nudge --------------------------
case_tool_calls_absent_no_nudge() {
  reset_case_env
  run_hook "$(jq -n '{hook_event_name: "PostToolBatch"}')"
  assert_no_nudge "tool-calls-absent-no-nudge"
}

# --- Case 5: 3 distinct types via the "Task" tool name -> no nudge -----------
case_task_name_counted() {
  reset_case_env
  run_hook "$(mk_batch \
    "$(mk_call Task shell-expert 'a')" \
    "$(mk_call Task docs-expert 'b')" \
    "$(mk_call Task code-review-expert 'c')")"
  assert_no_nudge "task-name-counted"
}

# --- Case 6: mixed 2 Agent + 1 Task, 3 distinct types -> no nudge ------------
case_mixed_names_counted() {
  reset_case_env
  run_hook "$(mk_batch \
    "$(mk_call Agent shell-expert 'a')" \
    "$(mk_call Task docs-expert 'b')" \
    "$(mk_call Agent code-review-expert 'c')")"
  assert_no_nudge "mixed-names-counted"
}

# --- Case 7: 1 agent call -> nudge -------------------------------------------
case_single_call_nudge() {
  reset_case_env
  run_hook "$(mk_batch "$(mk_call Agent shell-expert 'lone delegation')")"
  assert_nudge "single-call-nudge"
}

# --- Case 8: 2 agent calls, 2 distinct types -> nudge (count < 3) ------------
case_two_calls_nudge() {
  reset_case_env
  run_hook "$(mk_batch \
    "$(mk_call Agent shell-expert 'a')" \
    "$(mk_call Agent docs-expert 'b')")"
  assert_nudge "two-calls-nudge"
}

# --- Case 9: 3 calls, 2 distinct types (A,A,B) -> nudge (weak angle) ----------
case_weak_angle_nudge() {
  reset_case_env
  run_hook "$(mk_batch \
    "$(mk_call Agent shell-expert 'a1')" \
    "$(mk_call Agent shell-expert 'a2')" \
    "$(mk_call Agent docs-expert 'b')")"
  assert_nudge "weak-angle-nudge"
}

# --- Case 10: 3 calls same type, different prompts -> nudge -------------------
# The "same agent twice with different prompts does NOT count as two" case:
# not the replication shape (prompts differ), and only 1 distinct type.
case_same_type_varied_prompts_nudge() {
  reset_case_env
  run_hook "$(mk_batch \
    "$(mk_call Agent shell-expert 'p1')" \
    "$(mk_call Agent shell-expert 'p2')" \
    "$(mk_call Agent shell-expert 'p3')")"
  assert_nudge "same-type-varied-prompts-nudge"
}

# --- Case 11: jq absent -> fail-open WARN, no nudge --------------------------
case_jq_missing_fail_open() {
  reset_case_env
  local no_jq_path
  no_jq_path="$(build_path_without_jq)"
  run_hook "$(mk_batch "$(mk_call Agent shell-expert 'x')")" "$no_jq_path"
  assert_failopen "jq-missing-fail-open" "jq not on PATH"
}

# --- Case 12: empty stdin -> silent no nudge ---------------------------------
case_empty_stdin_no_nudge() {
  reset_case_env
  run_hook ""
  assert_no_nudge "empty-stdin-no-nudge"
}

# --- Case 13: malformed JSON -> fail-open, no nudge --------------------------
case_malformed_json_no_nudge() {
  reset_case_env
  run_hook 'not json {'
  assert_no_nudge "malformed-json-no-nudge"
}

# --- Case 14: SKIP_FANOUT_NUDGE=1 -> skip WARN, no nudge ---------------------
case_skip_bypass() {
  reset_case_env
  export SKIP_FANOUT_NUDGE=1
  run_hook "$(mk_batch "$(mk_call Agent shell-expert 'x')")"
  unset SKIP_FANOUT_NUDGE
  assert_failopen "skip-bypass" "SKIP_FANOUT_NUDGE=1"
}

# --- Case 15: concatenated multi-document stdin -> no nudge -------------------
# A lone-call first document (which alone WOULD nudge) concatenated with a
# second: the single-document guard must reject the whole input rather than
# decide from the first document only (shell-expert review, ADR-090).
case_multi_document_no_nudge() {
  reset_case_env
  local d1 d2
  d1="$(mk_batch "$(mk_call Agent shell-expert 'lone call would nudge')")"
  d2="$(mk_batch \
    "$(mk_call Agent shell-expert 'a')" \
    "$(mk_call Agent docs-expert 'b')" \
    "$(mk_call Agent code-review-expert 'c')")"
  run_hook "$(printf '%s\n%s' "$d1" "$d2")"
  assert_no_nudge "multi-document-no-nudge"
}

# --- Case 16: valid JSON, non-object tool_calls entry -> fail open ------------
# A scalar in tool_calls makes the counts query error (indexing a number);
# caught by `2>/dev/null || true` -> empty counts -> silent exit 0.
case_wrong_schema_no_nudge() {
  reset_case_env
  run_hook '{"hook_event_name":"PostToolBatch","tool_calls":[3,{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"p"}}]}'
  assert_no_nudge "wrong-schema-no-nudge"
}

info "fanout-nudge.sh (PostToolBatch hook) acceptance tests"
case_divergence_no_nudge
case_replication_no_nudge
case_no_agent_calls_no_nudge
case_tool_calls_absent_no_nudge
case_task_name_counted
case_mixed_names_counted
case_single_call_nudge
case_two_calls_nudge
case_weak_angle_nudge
case_same_type_varied_prompts_nudge
case_jq_missing_fail_open
case_empty_stdin_no_nudge
case_malformed_json_no_nudge
case_skip_bypass
case_multi_document_no_nudge
case_wrong_schema_no_nudge

echo "=================================="
if [ "$errors" -gt 0 ]; then
  echo "FAIL — $errors error(s)"
  exit 1
fi
echo "PASS — 0 errors"
exit 0
