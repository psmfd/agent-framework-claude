# ADR-088: SubagentStop Verdict Guard

**Status:** Accepted
**Date:** 2026-07-03

## Context and Problem Statement

The return contract's verdict lines (`AGENT-VERDICT:` in `rules/research-parallelism.md`, `**Verdict:**` in `rules/structured-review-format.md`) were self-report only — both rules' Enforcement lines named #24 as the tracked gap, and ADR-084 deliberately deferred mechanical enforcement. Doc-verified hook research confirmed the `SubagentStop` event delivers the subagent's final text (`last_assistant_message`) and can block-with-reason, keeping the subagent running with the reason as its next instruction — exactly the shape needed to force a missing verdict line to be appended before the response reaches the orchestrator. A blocking stop-event hook is a new enforcement-mechanism class for this repo (all prior guards are `PreToolUse` or git-native), with design tensions the existing conventions do not settle.

## Considered Options

* **Option A** — Fail-closed hook per ADR-057, scoped by a `settings.json` `agent_type` matcher listing the framework agents.
* **Option B** — Fail-open hook, in-hook dynamic scoping (`agent_type` resolves to a file in `~/.claude/agents/`), either-grammar verdict acceptance, `stop_hook_active` loop guard, announced `SKIP_SUBAGENT_VERDICT_GUARD=1` override.
* **Option C** — Status quo: consumer-side fail-closed defaults only (missing verdict → `PARTIAL` / `NEEDS_CHANGES`).

## Decision Outcome

Chosen option: **Option B**, because each of its deviations from house convention is load-bearing:

1. **Fail OPEN, inverting ADR-057.** For the `PreToolUse` guards, "deny" blocks one retryable action; for a stop-event hook, "block" forces the subagent to keep running. An indeterminate state (missing `jq`, absent/empty `last_assistant_message`) is not something the subagent can fix, so failing closed risks wedging it in a loop. This also matches the sibling `Stop` hook's never-block posture (`stop-preflight-check.sh`). The consumer-side defaults from Option C are retained as the authoritative backstop everywhere the hook does not fire — the hook enforces *presence*, never *truthfulness*, and its block reason explicitly instructs appending the verdict that matches the actual findings.
2. **Dynamic in-hook scoping over a settings matcher.** A matcher list duplicates the agent catalog into `settings.json` — a new drift surface on every agent add/remove. Checking `-f ~/.claude/agents/<agent_type>.md` makes the existing symlink the allowlist with zero maintenance, and fails open for built-ins (`general-purpose`, `Explore`, `Plan`), plugin-scoped, and unknown types.
3. **Either-grammar acceptance.** The hook passes on a terminal `AGENT-VERDICT:` line or a `**Verdict:**` line outside fenced code blocks. This resolves the advisory-mode collision (a review agent doing research work legitimately uses the research grammar — `agents/security-review-expert.md` now says so explicitly, and `rules/research-parallelism.md`'s "no second AGENT-VERDICT line" clause carries the matching exception) without the hook needing to know an invocation's mode; which grammar is semantically correct remains the consumer rules' job. The two review agents deliberately differ by advisory shape, not by inconsistency: `code-review-expert`'s advisory mode reviews a supplied artifact and verdicts on it (review grammar); `security-review-expert`'s advisory mode answers research questions (research grammar) — the rule states the distinction.
4. **One forced retry per stop cycle.** `stop_hook_active: true` allows unconditionally, so a non-compliant subagent is re-instructed at most once; the platform's own consecutive-block cap (documented as 8 for `Stop`; assumed shared) is a further backstop. No state files.

### Tradeoffs

* Good: the return contract is forced at the source for every framework agent in every project (user-level hook), making the fail-closed consumer defaults a rare path; zero-maintenance scoping; bounded worst case (one extra subagent turn).
* Bad: general-purpose agents on research fan-outs are not gated (the contract obligation lives in the orchestrator's brief, not the agent identity) — the batch-level counter tracked in #44 is the complement; a verdict quoted in an inline (unfenced) code span can false-pass; presence-checking can pressure an agent toward a rubber-stamp verdict, mitigated only by the reason text and unchanged consumer semantics.

## More Information

* #24 (phase 1 — closed by this change), #44 (phase 2: PostToolBatch fan-out counter)
* ADR-084 (deferral record), ADR-057 (the fail-closed convention this deviates from), ADR-083 (test-suite pattern — `tests/subagent-verdict-guard/`)
* `rules/research-parallelism.md`, `rules/structured-review-format.md` (Enforcement lines updated; backstop clauses added)
