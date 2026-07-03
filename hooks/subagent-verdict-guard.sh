#!/usr/bin/env bash
#
# subagent-verdict-guard.sh — Global SubagentStop hook (ADR-088)
#
# Blocks a framework custom agent from returning without its machine-parseable
# verdict line, delivering the block reason as the subagent's next instruction
# so it appends the line and stops again. Mechanically enforces the return
# contract from rules/research-parallelism.md (terminal AGENT-VERDICT line)
# and rules/structured-review-format.md (**Verdict:** line) — phase 1 of #24.
#
# Contract: exit 0 = allow the stop; exit 2 = block (stderr is delivered to
# the subagent as its next instruction, per the SubagentStop hook contract).
#
# Scope: enforced ONLY when the payload's agent_type resolves to a file in
# ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agents/<agent_type>.md — i.e. this
# framework's own custom agents. Built-ins (general-purpose, Explore, Plan,
# claude-code-guide, ...), plugin-scoped types, and unknown types always pass
# (fail open). Zero-maintenance by design: the agents/ symlink IS the
# allowlist, so catalog changes need no hook edit (a settings.json matcher
# was considered and rejected for exactly that drift reason — ADR-088).
#
# Verdict detection accepts EITHER grammar, so an agent legitimately using
# the other rule's form (e.g. a review agent doing advisory research work
# ends with AGENT-VERDICT per research-parallelism.md) is never false-blocked:
#   - a terminal `AGENT-VERDICT: COMPLETE|PARTIAL|BLOCKED` line — must be the
#     LAST non-blank line (research-parallelism.md Return Contract), or
#   - a `**Verdict:** PASS|PASS_WITH_WARNINGS|NEEDS_CHANGES|UNABLE_TO_REVIEW`
#     line anywhere outside a fenced code block (structured-review-format.md).
#
# Fail posture: fail OPEN — a DELIBERATE inversion of the ADR-057 fail-closed
# convention used by the PreToolUse guards. There, "deny" blocks one
# retryable action; here, "block" forces the subagent to keep running, so an
# indeterminate state (missing jq, absent/empty last_assistant_message) must
# not wedge a subagent in a loop it cannot fix. The consuming orchestrator's
# fail-closed defaults (missing verdict -> PARTIAL / NEEDS_CHANGES) remain
# the authoritative backstop wherever this hook does not fire. Matches the
# never-block posture of the sibling Stop hook (stop-preflight-check.sh).
#
# Loop safety: when stop_hook_active is true (this stop is already the result
# of a stop-hook block), allow unconditionally — at most ONE forced retry per
# stop cycle. The platform's own consecutive-block cap is a further backstop.
#
# Known accepted gaps (enforcement is presence, not truthfulness): the hook
# cannot verify the verdict VALUE matches the findings (the block reason
# instructs honesty; consumer rules own semantics); general-purpose agents on
# research fan-outs are not gated (the contract obligation lives in the
# orchestrator's brief, not the agent identity — see #44 for the batch-level
# phase 2); a verdict quoted in an inline code span (not a fenced block) can
# false-pass the review grammar.
#
# Override: SKIP_SUBAGENT_VERDICT_GUARD=1 (env) — announced, never silent.
# Exit codes: 0 allow, 2 block. Targets bash 3.2+.

set -uo pipefail

# --- Session bypass (announced — never silent) -------------------------------
if [ "${SKIP_SUBAGENT_VERDICT_GUARD:-}" = "1" ]; then
  printf 'WARN  [skip] SKIP_SUBAGENT_VERDICT_GUARD=1 set — subagent verdict guard bypassed\n' >&2
  exit 0
fi

INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

# --- Dependency guard: fail OPEN (see header — deliberate ADR-057 deviation) --
if ! command -v jq >/dev/null 2>&1; then
  printf 'subagent-verdict-guard: WARN — jq not on PATH; verdict check skipped (fail-open by design, ADR-088)\n' >&2
  exit 0
fi

# --- Loop guard: never block twice in one stop cycle -------------------------
stop_active="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // .stopHookActive // false' 2>/dev/null || true)"
[ "$stop_active" = "true" ] && exit 0

# --- Scope: framework custom agents only (fail open for everything else) -----
AGENTS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agents"
agent_type="$(printf '%s' "$INPUT" | jq -r '.agent_type // .agentType // ""' 2>/dev/null || true)"
[ -z "$agent_type" ] && exit 0
case "$agent_type" in */*|.*) exit 0 ;; esac   # path-unsafe type: not ours
[ -f "$AGENTS_DIR/$agent_type.md" ] || exit 0

# --- Final message (direct input field; absent/empty -> fail open) -----------
msg="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || true)"
if [ -z "$msg" ]; then
  printf 'subagent-verdict-guard: WARN — last_assistant_message absent/empty for %s; verdict check skipped (fail-open)\n' "$agent_type" >&2
  exit 0
fi

# --- Grammar 1: terminal AGENT-VERDICT line (research-parallelism.md) --------
# The LAST non-blank line (CRLF-safe, trailing-whitespace-tolerant on that
# line only) must be exactly the verdict — trailing prose after the verdict
# violates the terminal-line rule and does NOT pass.
has_terminal_agent_verdict() {
  printf '%s\n' "$1" | sed -e 's/\r$//' | awk '
    NF { line = $0 }
    END {
      sub(/[ \t]+$/, "", line)
      exit (line ~ /^AGENT-VERDICT: (COMPLETE|PARTIAL|BLOCKED)$/) ? 0 : 1
    }
  '
}

# --- Grammar 2: review verdict line (structured-review-format.md) ------------
# Anywhere in the message, but lines inside ```-fenced blocks are excluded so
# a quoted format example cannot false-pass. Longest alternative first so the
# alternation cannot short-match PASS inside PASS_WITH_WARNINGS.
has_review_verdict() {
  printf '%s\n' "$1" | sed -e 's/\r$//' | awk '
    /^```/ { infence = !infence; next }
    infence { next }
    /^\*\*Verdict:\*\*[ \t]+(PASS_WITH_WARNINGS|NEEDS_CHANGES|UNABLE_TO_REVIEW|PASS)([ \t]|$)/ { found = 1 }
    END { exit (found ? 0 : 1) }
  '
}

has_terminal_agent_verdict "$msg" && exit 0
has_review_verdict "$msg" && exit 0

# --- Block: deliver the fix as the subagent's next instruction ---------------
printf '%s\n' "subagent-verdict-guard: your response is missing its required machine-parseable verdict line (agent type: $agent_type). Append the verdict that MATCHES your actual findings — do not report COMPLETE or PASS to satisfy this check if your work is partial, blocked, or found problems. If you are a research/domain agent: make the LAST line of your response exactly 'AGENT-VERDICT: COMPLETE' (or PARTIAL or BLOCKED) with nothing after it (rules/research-parallelism.md Return Contract). If you are a review agent reporting on a diff or artifact: include a line of the exact form '**Verdict:** PASS' (or PASS_WITH_WARNINGS, NEEDS_CHANGES, UNABLE_TO_REVIEW) per rules/structured-review-format.md. Then stop." >&2
exit 2
