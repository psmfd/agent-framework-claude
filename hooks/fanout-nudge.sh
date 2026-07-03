#!/usr/bin/env bash
#
# fanout-nudge.sh — Global PostToolBatch hook (ADR-090)
#
# Advisory-only nudge toward the divergence minimum (3+ parallel agents from
# different angles) in rules/research-parallelism.md — phase 2 of #24. Where
# phase 1 (subagent-verdict-guard.sh, ADR-088) mechanically FORCES the verdict
# line, this hook only NOTIFIES: PostToolBatch fires once per parallel tool
# batch, AFTER the batch executed, and carries no task-classification field, so
# it cannot know whether the turn was Research (3+ mandatory), Implementation,
# or an exemption. It therefore never blocks — it emits a reminder the model
# reads before its next turn, and the load-bearing judgments (was this Research?
# were the exemption criteria met? are the angles substantively different?)
# remain self-report per the rule's Enforcement line.
#
# Contract: ALWAYS exit 0. The only variable is whether a nudge is emitted:
#   - stdout: a hookSpecificOutput.additionalContext JSON payload ONLY when
#     nudging (stdout is otherwise silent — mixing prose into it would break
#     the harness JSON parse).
#   - stderr: a human-visible `WARN  [fanout-nudge] ...` line alongside the
#     nudge (script-output-conventions.md; WARN = non-fatal, no exit effect).
#
# Signal (diversity-signal PRESENCE, never substantive divergence — the direct
# analog of ADR-088's "enforce presence, never truthfulness"):
#   n        = count of Agent/Task calls in the batch
#   ntypes   = distinct subagent_type among them
#   nprompts = distinct prompt bodies among them
# Decision:
#   n == 0                              -> no nudge (not a fan-out batch; the
#                                          common case — cheap short-circuit)
#   n >= 3 && ntypes >= 3               -> no nudge (clear divergence)
#   n >= 3 && ntypes == 1 && nprompts == 1
#                                       -> no nudge (the legitimate replication
#                                          shape, consensus-by-replication.md —
#                                          identical agent + identical prompt)
#   otherwise (1-2 calls, or 3+ with a
#   weak angle signal)                  -> advisory nudge
#
# Tool name: matches BOTH "Agent" (the current wire name) and "Task" (the
# earlier name it was renamed from, in a Claude Code 2.1.x release) so
# pre-rename transcripts still count — matched defensively (ADR-090).
#
# Fail posture: uniform fail-OPEN. Missing jq, empty stdin, malformed JSON, or
# a jq query error all exit 0 with no nudge — a missed advisory reminder costs
# nothing, and this hook (unlike the PreToolUse guards) has nothing to protect
# against by failing closed. Extends ADR-088's fail-open one step further: 088
# still blocks on a DETERMINATE violation (a verdict line is verifiably absent),
# but a fan-out counter cannot reach that certainty about a POLICY violation, so
# it never blocks at all.
#
# Override: SKIP_FANOUT_NUDGE=1 (env) — announced, never silent.
# Exit code: always 0. Targets bash 3.2+.

set -uo pipefail

# --- Session bypass (announced — never silent) -------------------------------
if [ "${SKIP_FANOUT_NUDGE:-}" = "1" ]; then
  printf 'WARN  [skip] SKIP_FANOUT_NUDGE=1 set — fan-out advisory nudge bypassed\n' >&2
  exit 0
fi

INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

# --- Dependency guard: fail OPEN (see header — advisory, nothing to protect) --
if ! command -v jq >/dev/null 2>&1; then
  printf 'fanout-nudge: WARN — jq not on PATH; advisory nudge skipped (fail-open by design, ADR-090)\n' >&2
  exit 0
fi

# --- Parse guard: malformed input -> fail open -------------------------------
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

# --- Single-document guard: one batch = one decision -------------------------
# `jq -e .` accepts CONCATENATED documents (it only checks the last value), so
# a multi-document stdin would leave set -- keeping only the first triple and
# silently dropping the rest. Reject anything but exactly one document (jq -rc
# '1' emits one line per input document) — fail open, never a nudge.
[ "$(printf '%s' "$INPUT" | jq -rc '1' 2>/dev/null | wc -l | tr -d '[:space:]')" = "1" ] || exit 0

# --- Signal extraction: one jq pass -> "n ntypes nprompts" -------------------
# `.tool_calls[]?` no-ops when tool_calls is null/absent (determinate zero).
counts="$(printf '%s' "$INPUT" | jq -r '
  [ .tool_calls[]? | select(.tool_name == "Agent" or .tool_name == "Task") ] as $a
  | ($a | length) as $n
  | ($a | map(.tool_input.subagent_type // "unknown") | unique | length) as $t
  | ($a | map(.tool_input.prompt // "")            | unique | length) as $p
  | "\($n) \($t) \($p)"
' 2>/dev/null || true)"

[ -z "$counts" ] && exit 0                 # jq query error -> fail open

# shellcheck disable=SC2086  # deliberate word-split of the three integers
set -- $counts
n="${1:-0}"; ntypes="${2:-0}"; nprompts="${3:-0}"

# Non-numeric anywhere -> indeterminate -> fail open
case "$n$ntypes$nprompts" in *[!0-9]*) exit 0 ;; esac

# --- Decision: no-nudge fast paths -------------------------------------------
[ "$n" -eq 0 ] && exit 0                                        # not a fan-out
[ "$n" -ge 3 ] && [ "$ntypes" -ge 3 ] && exit 0                 # clear divergence
[ "$n" -ge 3 ] && [ "$ntypes" -eq 1 ] && [ "$nprompts" -eq 1 ] && exit 0  # replication

# --- Advisory nudge ----------------------------------------------------------
ctx="This tool batch contained ${n} agent call(s) across ${ntypes} distinct subagent_type(s). If this turn is a Research task, rules/research-parallelism.md requires a divergence minimum of 3+ parallel agents from different angles (3+ distinct subagent_types — the same agent invoked again with a different prompt does NOT add an angle). If this is an Implementation delegation, a Verified Single-Fact Lookup, or the consensus-by-replication convergence shape (identical agent + identical prompt), this reminder does not apply — disregard it. Advisory only; nothing was blocked, and task classification, exemption validity, and substantive divergence of angles remain your own call."

# stdout: JSON only (jq -n escapes the payload safely)
jq -n --arg ctx "$ctx" \
  '{hookSpecificOutput: {hookEventName: "PostToolBatch", additionalContext: $ctx}}'

# stderr: human-visible advisory line (never affects exit code)
printf 'WARN  [fanout-nudge] batch had %s agent call(s), %s distinct type(s); advisory divergence reminder (research-parallelism.md)\n' \
  "$n" "$ntypes" >&2

exit 0
