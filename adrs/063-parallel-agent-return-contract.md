# ADR-063: Machine-parseable return contract for parallel agents

**Status:** Accepted
**Date:** 2026-06-01

## Context and Problem Statement

ADR-016 mandates fanning out to three or more parallel agents and synthesizing their results, but specifies no contract for how an agent returns its result — the orchestrator parses free-form prose to aggregate. `structured-review-format.md` already defines a `**Verdict:**` line for review output, but most parallel agents are research/design agents with no such line. A return contract must make aggregation deterministic across both kinds of agent without creating two conflicting verdict vocabularies, and without re-opening the loophole class where an agent emits a vacuously-compliant artifact.

## Considered Options

* **Option A** — One shared verdict enum for all parallel agents. Collides: research agents have no findings table, so review verdicts (`PASS`/`NEEDS_CHANGES`) are semantically empty for them.
* **Option B** — A separate, distinct token for non-review agents (`AGENT-VERDICT:`), with review agents keeping the existing `**Verdict:**`; the obligation lives on the orchestrator's delegation brief and the verdict line is additive to each agent's normal output.
* **Option C** — Add a verdict requirement to every agent wrapper's `## Output format` section. Touches ~14 wrappers × 2 platforms and re-creates the "missed artifact" drift risk.

## Decision Outcome

Chosen option: **Option B**. A new `## Return Contract` section in `rules/research-parallelism.md` requires each parallel agent to end its response with a bounded executive summary followed by a single terminal verdict line. Non-review agents use `AGENT-VERDICT: COMPLETE | PARTIAL | BLOCKED`; review agents (`code-review-expert`, `security-review-expert`, `linter`) keep `structured-review-format.md`'s `**Verdict:** PASS | PASS_WITH_WARNINGS | NEEDS_CHANGES` and emit no `AGENT-VERDICT:` line. The two distinct tokens give the orchestrator an unambiguous anchor and avoid forking the review vocabulary.

The obligation is framed as an **orchestrator delegation duty**: the orchestrator requests the contract in each agent brief, and the verdict line is **additive and terminal**, so it composes with an agent wrapper's existing output template rather than competing with it. This deliberately avoids editing agent wrappers (Option C) and therefore avoids the parallel-artifact drift the research-parallelism rule itself warns against. Two loopholes are closed in the rule text: the executive summary is a required, bounded field (a non-committal summary while a blocker exists is non-compliant), and the verdict line must be the final line with nothing after it. The rationale is deterministic aggregation — the upstream source's output-truncation rationale is deliberately not adopted (Claude's Agent tool returns full output).

This **extends** ADR-016; it does not supersede it (the parallelism convention is unchanged). ADR-016 is left intact.

### Tradeoffs

* Good: parallel-agent results aggregate deterministically; `BLOCKED` returns become an explicit synthesis gate surfaced to the user.
* Good: no wrapper churn and no competing output-format artifact to drift; review agents are unaffected.
* Bad: compliance depends on the orchestrator including the contract in each brief — it is a behavioral convention, not a mechanical gate.
* Bad: enforcement gap — `validate.sh` checks rule/instruction parity but cannot verify that agent responses actually carry the verdict line. Accepted until a dedicated check is justified.

## More Information

* Extends [ADR-016](016-research-parallelism.md) (research parallelism with minimum three agents).
* Issue #191. Design fan-out: code-review-expert (token/enum/loophole/requirement-fidelity), docs-expert (section prose), ai-crossplatform-expert (mirror parity, Copilot caveat, ADR posture, enforcement gap).
* Related: `rules/structured-review-format.md` (the review verdict vocabulary this contract defers to).
