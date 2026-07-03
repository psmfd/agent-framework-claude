#!/usr/bin/env bash
#
# run-tests.sh — acceptance tests for hooks/subagent-verdict-guard.sh (the
# SubagentStop verdict guard, ADR-088; phase 1 of #24)
#
# Contract under test: stdin=JSON SubagentStop payload with agent_type and
# last_assistant_message. Exit 0 = allow the stop, 2 = block (stderr reason
# delivered to the subagent). Fail OPEN on indeterminate state (missing jq,
# absent message) — the deliberate inversion of the PreToolUse guards'
# ADR-057 fail-closed posture (see the hook header and ADR-088).
#
# Coverage:
#   1. terminal AGENT-VERDICT line, gated agent            -> silent allow
#   2. **Verdict:** with a reason line below, review agent -> silent allow
#   3. verdict missing entirely, gated agent               -> block (rc 2)
#   4. AGENT-VERDICT present but trailing prose follows    -> block
#      (terminal-line rule: the verdict must be the final non-blank line)
#   5. **Verdict:** only inside a ```-fenced block         -> block
#      (a quoted format example is not a verdict)
#   6. CRLF line endings + trailing spaces on the verdict  -> silent allow
#   7. agent_type not in the agents dir (general-purpose)  -> allow (ungated)
#   8. path-shaped agent_type (../evil)                    -> allow (ungated)
#   9. jq absent from PATH                                 -> allow with WARN
#      (fail-open deviation — ADR-088)
#  10. empty stdin                                         -> silent allow
#  11. last_assistant_message absent                       -> allow with WARN
#  12. stop_hook_active: true                              -> silent allow
#      (loop guard: at most one forced retry per stop cycle)
#  13. SKIP_SUBAGENT_VERDICT_GUARD=1                       -> allow with WARN
#  14. non-review gated agent using the review grammar     -> silent allow
#      (either-grammar acceptance — consumer rules own which is right)
#  15. review-governed agent's advisory output ending in   -> silent allow
#      AGENT-VERDICT (the #24/ADR-088 collision case)
#
# Every case pins CLAUDE_CONFIG_DIR to a throwaway directory whose agents/
# holds exactly three fixture files (shell-expert.md, code-review-expert.md,
# security-review-expert.md), so the real ~/.claude is never consulted and
# the gating set is controlled.
#
# Output per rules/script-output-conventions.md.
# Exit codes: 0 all pass, 1 one or more failures, 2 precondition failure.
#
# Targets bash 3.2+ (the hook's floor). Run: bash tests/subagent-verdict-guard/run-tests.sh

# -e is intentionally omitted: a test runner must continue past a failing
# case to report all results; failures are tracked via the `errors` counter.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../../hooks/subagent-verdict-guard.sh"

ok()   { echo "OK    [$1] $2"; }
err()  { echo "ERROR [$1] $2" >&2; }
info() { echo "INFO  $*"; }

errors=0
TMPDIRS=()
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
cleanup() { local d; for d in ${TMPDIRS[@]+"${TMPDIRS[@]}"}; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

for cmd in jq bash awk sed; do
  command -v "$cmd" >/dev/null 2>&1 || { err "env" "$cmd is required but not on PATH"; exit 2; }
done
[ -f "$HOOK" ] || { err "env" "hook not found at $HOOK"; exit 2; }

# Resolve the interpreter ONCE, before any case restricts PATH.
BASH_BIN="$(command -v bash)"

# Throwaway config dir: agents/ holds exactly the gated fixture set.
CONFIG_DIR="$(mktemp -d)"
TMPDIRS+=("$CONFIG_DIR")
# Stdin payload file for run_hook (cleanup handles files as well as dirs).
INFILE="$(mktemp)"
TMPDIRS+=("$INFILE")
mkdir -p "$CONFIG_DIR/agents"
: > "$CONFIG_DIR/agents/shell-expert.md"
: > "$CONFIG_DIR/agents/code-review-expert.md"
: > "$CONFIG_DIR/agents/security-review-expert.md"

# Synthetic PATH for the jq-absent case: symlink every tool the hook needs
# EXCEPT jq into a throwaway dir (same technique as the sibling suites —
# searching real directories for a "present but not jq" combination is
# host-layout-dependent; symlinking the wanted set is deterministic).
build_path_without_jq() {
  local dir c src
  dir="$(mktemp -d)"
  TMPDIRS+=("$dir")
  for c in cat sed awk printf tr; do
    src="$(command -v "$c" 2>/dev/null)" || continue
    case "$src" in /*) ln -s "$src" "$dir/$c" ;; esac
  done
  printf '%s' "$dir"
}

# Build the SubagentStop payload via jq -n (correct escaping for multi-line
# message bodies). $3 optionally sets stop_hook_active=true.
mk_input() {
  local agent_type="$1" message="${2-}" stop_active="${3:-false}"
  jq -n --arg at "$agent_type" --arg msg "$message" --argjson sa "$stop_active" \
    '{hook_event_name: "SubagentStop", agent_type: $at, last_assistant_message: $msg, stop_hook_active: $sa}'
}

# Run the hook with stdin payload $1. Optional env prefix vars are handled by
# the callers exporting/unsetting around this. Sets globals OUT and RC.
OUT="" RC=0
run_hook() {
  local payload="$1" use_path="${2:-$PATH}"
  RC=0
  # Feed stdin via file redirection, never `printf | hook`: on skip paths the
  # hook exits before reading stdin, and under pipefail the printf side can
  # lose the pipe-close race (EPIPE) and poison the pipeline result — the
  # bash-3.2 CI failure diagnosed in PR #59 and hardened here per #60.
  printf '%s' "$payload" > "$INFILE"
  OUT="$(CLAUDE_CONFIG_DIR="$CONFIG_DIR" PATH="$use_path" "$BASH_BIN" "$HOOK" < "$INFILE" 2>&1)" || RC=$?
}

assert_silent_allow() {
  local name="$1"
  if [ "$RC" = "0" ] && [ -z "$OUT" ]; then
    ok "$name" "silent allow (exit 0, no output)"
  else
    err "$name" "expected silent allow, got exit $RC output: $(printf '%s' "$OUT" | tr '\n' '|')"
    errors=$((errors + 1))
  fi
}

assert_result() {
  local name="$1" exp_rc="$2" substr="$3"
  if [ "$RC" != "$exp_rc" ]; then
    err "$name" "expected exit $exp_rc, got exit $RC — output: $(printf '%s' "$OUT" | tr '\n' '|')"
    errors=$((errors + 1))
    return
  fi
  case "$OUT" in
    *"$substr"*) ok "$name" "exit $RC as expected (substring: $substr)" ;;
    *)
      err "$name" "exit $RC as expected but missing substring '$substr' — output: $(printf '%s' "$OUT" | tr '\n' '|')"
      errors=$((errors + 1))
      ;;
  esac
}

reset_case_env() {
  unset SKIP_SUBAGENT_VERDICT_GUARD
}

# --- Case 1: terminal AGENT-VERDICT, gated agent -> silent allow -------------
case_terminal_verdict_allow() {
  reset_case_env
  run_hook "$(mk_input shell-expert $'Findings here.\n\nAGENT-VERDICT: COMPLETE')"
  assert_silent_allow "terminal-verdict-allow"
}

# --- Case 2: review verdict with reason line below -> silent allow -----------
case_review_verdict_allow() {
  reset_case_env
  run_hook "$(mk_input code-review-expert $'## Findings\n\ntable here\n\n**Verdict:** UNABLE_TO_REVIEW\ndiff artifact missing')"
  assert_silent_allow "review-verdict-allow"
}

# --- Case 3: verdict missing entirely -> block --------------------------------
case_missing_verdict_block() {
  reset_case_env
  run_hook "$(mk_input shell-expert 'Findings but no verdict line at all.')"
  assert_result "missing-verdict-block" 2 "missing its required machine-parseable verdict line"
}

# --- Case 4: AGENT-VERDICT present but trailing prose follows -> block --------
# The terminal-line rule: no text may follow the verdict line.
case_trailing_prose_block() {
  reset_case_env
  run_hook "$(mk_input shell-expert $'AGENT-VERDICT: COMPLETE\n\nP.S. one more footnote.')"
  assert_result "trailing-prose-block" 2 "AGENT-VERDICT"
}

# --- Case 5: review verdict only inside a fenced block -> block ---------------
case_fenced_verdict_block() {
  reset_case_env
  run_hook "$(mk_input code-review-expert $'The format is:\n```\n**Verdict:** PASS\n```\nbut I forgot my own.')"
  assert_result "fenced-verdict-block" 2 "missing its required machine-parseable verdict line"
}

# --- Case 6: CRLF endings + trailing spaces on the verdict -> allow -----------
case_crlf_verdict_allow() {
  reset_case_env
  run_hook "$(mk_input shell-expert $'Findings.\r\n\r\nAGENT-VERDICT: PARTIAL  \r')"
  assert_silent_allow "crlf-verdict-allow"
}

# --- Case 7: agent_type not in the agents dir -> allow (ungated) --------------
case_ungated_type_allow() {
  reset_case_env
  run_hook "$(mk_input general-purpose 'no verdict anywhere')"
  assert_silent_allow "ungated-type-allow"
}

# --- Case 8: path-shaped agent_type -> allow (ungated, defensive) --------------
case_path_shaped_type_allow() {
  reset_case_env
  run_hook "$(mk_input '../shell-expert' 'no verdict anywhere')"
  assert_silent_allow "path-shaped-type-allow"
}

# --- Case 9: jq absent -> allow with WARN (fail-open, ADR-088) -----------------
case_jq_missing_fail_open() {
  reset_case_env
  local no_jq_path
  no_jq_path="$(build_path_without_jq)"
  run_hook "$(mk_input shell-expert 'no verdict')" "$no_jq_path"
  assert_result "jq-missing-fail-open" 0 "jq not on PATH; verdict check skipped"
}

# --- Case 10: empty stdin -> silent allow --------------------------------------
case_empty_stdin_allow() {
  reset_case_env
  run_hook ""
  assert_silent_allow "empty-stdin-allow"
}

# --- Case 11: last_assistant_message absent -> allow with WARN -----------------
case_message_absent_fail_open() {
  reset_case_env
  run_hook "$(jq -n '{hook_event_name: "SubagentStop", agent_type: "shell-expert"}')"
  assert_result "message-absent-fail-open" 0 "last_assistant_message absent/empty"
}

# --- Case 12: stop_hook_active true -> silent allow (loop guard) ---------------
case_stop_hook_active_allow() {
  reset_case_env
  run_hook "$(mk_input shell-expert 'still no verdict' true)"
  assert_silent_allow "stop-hook-active-allow"
}

# --- Case 13: SKIP_SUBAGENT_VERDICT_GUARD=1 -> allow with WARN -----------------
case_skip_bypass() {
  reset_case_env
  export SKIP_SUBAGENT_VERDICT_GUARD=1
  run_hook "$(mk_input shell-expert 'no verdict')"
  unset SKIP_SUBAGENT_VERDICT_GUARD
  assert_result "skip-bypass" 0 "SKIP_SUBAGENT_VERDICT_GUARD=1"
}

# --- Case 14: non-review agent using the review grammar -> allow ---------------
# Either-grammar acceptance: presence is the hook's job; which grammar is
# semantically right for the agent is the consumer rules' job.
case_cross_grammar_allow() {
  reset_case_env
  run_hook "$(mk_input shell-expert $'analysis\n\n**Verdict:** PASS')"
  assert_silent_allow "cross-grammar-allow"
}

# --- Case 15: review-governed agent in advisory mode -> allow -------------------
# The collision this hook's either-grammar design exists to close (#24,
# ADR-088): security-review-expert's advisory output is a research response
# and ends with the AGENT-VERDICT terminal line per research-parallelism.md's
# advisory exception — the hook must not force a **Verdict:** line onto it.
case_review_agent_advisory_allow() {
  reset_case_env
  run_hook "$(mk_input security-review-expert $'No diff was in scope; advisory analysis follows.\n\nAGENT-VERDICT: COMPLETE')"
  assert_silent_allow "review-agent-advisory-allow"
}

info "subagent-verdict-guard.sh (SubagentStop hook) acceptance tests"
case_terminal_verdict_allow
case_review_verdict_allow
case_missing_verdict_block
case_trailing_prose_block
case_fenced_verdict_block
case_crlf_verdict_allow
case_ungated_type_allow
case_path_shaped_type_allow
case_jq_missing_fail_open
case_empty_stdin_allow
case_message_absent_fail_open
case_stop_hook_active_allow
case_skip_bypass
case_cross_grammar_allow
case_review_agent_advisory_allow

echo "=================================="
if [ "$errors" -gt 0 ]; then
  echo "FAIL — $errors error(s)"
  exit 1
fi
echo "PASS — 0 errors"
exit 0
