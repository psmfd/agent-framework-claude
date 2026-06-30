---
description: 'Convergence fan-out — replicate the same agent N times on identical prompts and aggregate via a ladder for high-confidence singular answers'
---

# Consensus by Replication

This rule is mandatory, not advisory, when the conditions below are met. It is the **convergence** fan-out shape; [`research-parallelism.md`](research-parallelism.md) is the complementary **divergence** shape. The two are distinct and composable — replication is not a substitute for the divergence minimum.

## When This Rule Applies

Use replication — not divergence — when BOTH hold:

1. The question has a single best answer (not a set of valid perspectives to synthesize).
2. The risk is that any single agent run could be a statistical outlier, so independent reasoning over identical inputs is what adds confidence.

**Decision test:** if you would phrase the agent prompts *differently* to get different angles, that is divergence — use `research-parallelism.md`. If you would phrase them *identically* and want independent reasoning to converge, that is replication — use this rule.

Typical triggers: validating a critical security/compliance judgement against a specific artifact; confirming a generated output satisfies a precise specification; adjudicating a contested factual claim in one narrow domain; producing a final binding recommendation downstream decisions depend on.

## When This Rule Does Not Apply

- Exploration, comparison, or trade-off analysis, or any task where different agents bring different domain knowledge — that is divergence (`research-parallelism.md`).
- Routine tasks where a single well-prompted agent pass suffices — replication's N× cost buys nothing there.
- Replication does not apply as a routine quality gate; it is a targeted confidence mechanism for high-stakes singular answers.

## Mechanism

Invoke the SAME agent with IDENTICAL prompts N times. Each invocation is independent — no invocation sees another's output before producing its own.

- **Claude Code** — N concurrent `Agent` invocations with the same `subagent_type` and identical prompt bodies.

Minimum N is 3 (N=2 yields no majority and forces every split to escalate). Default N is 3; 5 is the practical ceiling unless the user explicitly requests more. State the chosen N and the reason in the task-classification announcement — replication multiplies token cost by N.

## Variance Guard

Replication only produces independent signal if the N responses actually vary. At low sampling variance the same agent can return near-identical answers, and **identical answers are not consensus** — they are a single sample repeated. Before applying the ladder, assess whether the responses are genuinely independent: if a majority of responses are substantially identical (e.g. they share long verbatim spans in the same position), treat the run as an **N=1 signal**, record the low variance, and do not report it as agreement. Escalate to the user rather than claim a false unanimous result.

## Aggregation Ladder

First, drop any response whose return verdict is `BLOCKED` (see Return Contract in `research-parallelism.md`) from the denominator. If more than half of N returned `BLOCKED`, escalate to the user before laddering — the sample is too small to trust. Then apply, in order:

### Unanimous — adopt

All non-BLOCKED responses reach the same conclusion (and the Variance Guard passed). Adopt it. Record the unanimous outcome in the Agent Efficacy Report; no dissent section needed.

### Majority — adopt with documented dissent

A strict majority (more than half of the non-BLOCKED responses) agrees. Adopt the majority conclusion and document the minority position and the specific points of divergence. The dissent is informational, not blocking.

### Even split — escalate to the user

No strict majority exists (e.g. N=4 split 2/2, or a three-way split). **Full stop:** do not pick a winner and do not autonomously add more replication runs to break the tie. Surface every position to the user, stating what each holds and why the split occurred, without advocating for either. The user decides; re-running requires explicit user instruction.

### Singleton novel — adopt majority, credit the addendum

N−1 responses agree and one surfaces a distinct, material concern the majority did not raise (an orthogonal risk or missed requirement, not a disagreement about the answer). This is **additive, never a veto**: adopt the majority conclusion AND append the novel finding as a credited addendum ("one invocation raised the following concern not surfaced by the majority"). If the novel point is minor or orthogonal, log it in the dissent section and proceed with the majority.

### Verdict interaction

A `PARTIAL` return counts but is provisional — the unresolved items it names become recorded gaps in the consensus. When the replicated agent is a review agent governed by `structured-review-format.md`, ladder on its `**Verdict:**` line (`PASS` = accept, `NEEDS_CHANGES` = reject, `PASS_WITH_WARNINGS` = provisional) rather than on `AGENT-VERDICT`. The synthesizer emits one overall verdict for the replication run so a parent orchestrator can aggregate it.

## Anti-Patterns

| Anti-pattern | Why it fails |
|---|---|
| Replication on a divergence task | N identical agents produce N copies of one answer — no convergence signal, and it dodges the required divergence fan-out |
| N = 2 | Any disagreement forces escalation — there is no majority to adopt |
| Treating low-variance identical outputs as agreement | False consensus — see the Variance Guard |
| Letting invocations see each other's output before responding | Destroys independence; the first response anchors the rest |
| Picking the "best-sounding" response instead of applying the ladder | Reintroduces the subjective judgement replication was meant to remove |
| Adding replication runs to break a genuine even split | Evades the mandatory user escalation |
| Replicating when one authoritative pass suffices | Pays N× cost for no reliability gain |

## Token Cost

Replication multiplies token cost by N. Reserve it for tasks whose confidence requirement justifies the expense: confirm the "When This Rule Applies" criteria, pick the smallest N that yields a reliable majority (default 3), and prefer a single well-prompted pass when cost is constrained and the task is not on a security, compliance, or binding-decision path.

## Agent Efficacy Report Additions

Replication runs extend the standard Agent Efficacy Report (defined in `research-parallelism.md`) with a block, added after the agent's row in the agent table:

```text
### Replication Run

- Agent: <name>, N: <count>
- Variance: <sufficient | low — treated as N=1> (observed agreement rate)
- Outcome: Unanimous | Majority (N-k dissenting) | Even split | Singleton novel
- Dissent: <minority position, or "None">
- Novel finding: <the finding and whether incorporated, or "None">
- Decision: <what was adopted and why; for an even split, the verbatim user-escalation>
```

## Relationship to Research Parallelism

Divergence fans out to DIFFERENT agents for complementary perspectives; replication fans out to the SAME agent for a convergence signal. `research-parallelism.md`'s rule that "the same agent invoked twice does NOT count as two agents" governs the divergence minimum-of-three count only — it does not prohibit replication, which is this separate, deliberately-chosen shape with its own applicability test. The shapes compose: a divergence phase may identify the right agent for a critical judgement, then replication validates that agent's conclusion. When both run in one workflow, produce a separate Agent Efficacy Report block for each.
