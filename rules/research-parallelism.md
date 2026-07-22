---
description: 'Enforce multi-agent research with minimum three agents, quorum-based synthesis, and agent efficacy reporting'
---

# Research Parallelism

**Enforcement:** SubagentStop hook subagent-verdict-guard.sh (verdict-line presence on framework custom agents — ADR-088); PostToolBatch hook fanout-nudge.sh (advisory nudge on a batch-local `Agent`-call count / distinct-`subagent_type` signal — ADR-090); self-report only for task-classification accuracy, exemption validity, substantive divergence of angles, and any fan-out spread across separate batches or turns (#44)

This rule is mandatory, not advisory. When the orchestrator protocol classifies a task as Research, this rule applies in full. There are no soft opt-outs. See the Fan-Out Shapes and Aggregation Policy table in [orchestrator-protocol.md](orchestrator-protocol.md) for how this shape's aggregation compares to replication and multi-reviewer commands.

## When This Rule Applies

Any task that involves:

- Investigating a question or debugging a problem
- Exploring solutions or approaches
- Researching unfamiliar territory or technology
- Evaluating libraries, tools, or patterns
- Making architecture or design decisions
- Setting up infrastructure, CI/CD, branch policies, or deployment configuration
- Comparing alternatives or trade-offs
- Answering questions that touch domain expertise covered by custom agents

If the task matches ANY of the above, this rule applies. The question is never "is this complex enough to warrant research?" — it is "does this involve any investigation, evaluation, or domain knowledge?" If yes, fan out.

This list governs tasks already classified **Research** under `orchestrator-protocol.md`. The only task-classification-time carve-out is the Verified Single-Fact Lookup exemption in that rule's Narrow Exemptions — a bounded, four-criteria test applied *before* a task reaches this list, never a judgment call made from inside it. Once a task is classified Research, "no soft opt-outs" (above) is absolute: there is no post-classification escape hatch, and nothing in this rule creates one.

## Requirements

- **Fan out with a minimum of 3 parallel agents**, each approaching the problem from a different angle or perspective. Fewer than 3 agents is a protocol violation unless fewer than 3 relevant agents exist in the catalog.
- **Wait for all agents to return** before synthesizing a response. Do not present partial results or act on a single agent's output.
- **Synthesize the best-of-breed answer** by comparing and combining agent results — do not simply pick one.
- **If agents disagree**, highlight the disagreement and explain which perspective is strongest and why.

## What Counts Toward the Minimum

- Custom agents from the agent catalog count.
- General-purpose agents count, but only when no custom agent covers their assigned angle.
- The same agent invoked twice with different prompts does NOT count as two agents. This governs the divergence minimum only — deliberately replicating one agent on identical prompts is a separate, complementary shape (the convergence shape), not a violation of it.
- For a task with a single best answer where independent reasoning over identical inputs adds the confidence, use the convergence shape instead of divergence — see [`consensus-by-replication.md`](consensus-by-replication.md).

## Return Contract

Every parallel agent's response must be aggregable without parsing free-form prose. The orchestrator MUST request this contract in each delegation brief, and each agent MUST end its response with a bounded executive summary followed by a single machine-parseable verdict line, optionally preceded by a fenced expertise-candidates block per `expertise-capture.md`. The verdict line MUST be the final line of the response — no text, whitespace, or footnotes may follow it. The purpose is deterministic aggregation, not output-truncation insurance. The aggregation algorithm this contract feeds is defined in `### Synthesis Procedure` below.

**Executive summary** — a 2–5 sentence paragraph stating the question the agent addressed, its principal finding or recommendation, and any blocking concern or open dependency. A summary that is only positive or non-committal while the agent identified a blocker is non-compliant.

**Verdict line** — non-review agents end with the terminal line `AGENT-VERDICT: <value>`:

- `COMPLETE` — the delegated question is answered; findings are ready to synthesize.
- `PARTIAL` — part of the question is answered; the unresolved items are named in the summary.
- `BLOCKED` — the agent could not proceed (missing context, conflicting requirement, or a question outside its domain); the reason is named in the summary.

Review agents governed by `structured-review-format.md` (`code-review-expert`, `security-review-expert`, `linter`) use that rule's `**Verdict:** PASS | PASS_WITH_WARNINGS | NEEDS_CHANGES | UNABLE_TO_REVIEW` line as their verdict and do NOT emit a second `AGENT-VERDICT:` line — except when a review agent is answering a research question rather than reviewing an artifact (e.g. `security-review-expert`'s documented advisory mode): that output is a research response and ends with the non-review `AGENT-VERDICT:` terminal line above instead. The distinction is what the response is: reviewing a supplied artifact (even a draft or design) takes the review verdict; a pure advisory/research answer takes the research contract. That rule also defines a fail-closed default when the verdict line is missing entirely — see `structured-review-format.md`.

**Synthesizer obligations** — the orchestrator treats a non-review agent response with no verdict line as `PARTIAL`; treats a review-agent response with no `**Verdict:**` line as `NEEDS_CHANGES` per the fail-closed default in `structured-review-format.md` (never `PARTIAL` and never `PASS`); surfaces any `BLOCKED` or `UNABLE_TO_REVIEW` verdict to the user before synthesizing; and reuses each agent's executive summary as the "key contributions" entry in the Agent Efficacy Report. Where Claude Code hooks are active, the SubagentStop guard (`hooks/subagent-verdict-guard.sh`, ADR-088) forces the verdict line before a framework custom agent can return; these consumer-side defaults remain authoritative everywhere the hook does not fire (hooks disabled, ungated agent types such as general-purpose, non-hook surfaces) — the hook enforces presence, never truthfulness.

### Synthesis Procedure

The synthesizer follows two ordered steps. Skipping the claims table and going straight to prose is the exact gap this section closes — `consensus-by-replication.md` has a procedural aggregation algorithm for its shape; divergence synthesis did not, until now.

**Step 1 — Claims table (required, before prose).** Before writing any synthesized prose, the synthesizer builds a claims table with one row per agent:

| Agent | Claim / finding | Verdict | Confidence / basis |
| --- | --- | --- | --- |
| `<agent-name>` | The agent's principal finding or recommendation, one line | `COMPLETE` \| `PARTIAL` \| `BLOCKED` (or the review-format verdict) | What the agent grounded the claim in — first-party docs, code read, prior art — or "unstated" if the agent did not say |

Populate the table from each agent's executive summary and verdict line only — do not infer a claim the agent did not make. (An expertise-candidates block in a return is not a claim and never enters this table — it is handed to the separate gate/coalesce/approval procedure in `expertise-capture.md`.) A row the synthesizer cannot fill is marked "unstated," never invented. If a majority of rows are "unstated," that is not normal — it means the agents' executive summaries were non-compliant with the Return Contract's requirement to state basis (see the executive-summary paragraph above); flag it rather than proceeding as if the gap were expected.

**Step 2 — Prose synthesis (after the table, informed by it).** With the table built, the synthesizer writes the best-of-breed answer:

- Claims present in the table with matching verdicts across agents are adopted directly — no further judgment call needed.
- Claims that conflict (same question, different answers) are the disagreements this rule already requires surfacing — the table makes a conflict visible instead of relying on the synthesizer's recall of free-form prose.
- Claims graded `BLOCKED` are excluded from the adopted answer and surfaced per the Synthesizer obligations above.

The claims table does not replace the qualitative judgment of picking the strongest perspective when reasonable people could disagree — it bounds that judgment to the claims actually made, rather than a paraphrase from memory.

### Crashed or Empty-Output Subagent

An `Agent` invocation that crashes, times out, or returns empty/unparseable output is treated as `BLOCKED` for aggregation purposes — the same bucket a review agent's `UNABLE_TO_REVIEW` or missing-verdict state falls into (see `structured-review-format.md`). Do not silently drop the agent from the fan-out count, and do not retry it automatically more than once. Record the failure verbatim (error text, or "no output returned") in the Agent Efficacy Report's agent-table row for that agent, in place of "key contributions." A crash that drops the surviving agent count below the divergence minimum of 3 (`## Requirements` above) is itself a disagreement-worthy signal the Synthesizer obligations require surfacing to the user before synthesizing — do not silently backfill with a replacement agent to restore the count without telling the user why the original run fell short.

## Agent-behavioral Fan-out Composition

When the task is an agent-behavioral fix — a change that modifies constraint language, boundary conditions, or enumerated prohibited actions in an agent file or rule — the fan-out MUST include `code-review-expert` for requirement-fidelity review of the proposed text.

### When this applies

- Closing a documented boundary violation
- Correcting a known failure mode in agent behavior
- Codifying behavioral guidance that prohibits specific actions or rationalizations

This does not apply to additive knowledge changes (new domain facts, examples, or reference content), typo fixes, or structural-only edits that do not alter the semantic content of a constraint.

### Why code-review-expert

Two distinct failure modes have been observed in agent-behavioral fixes:

- **Missed artifact** — the fix targets the correct section of the agent file but a secondary section or template block preserves the old behavior. The fix ships incomplete and the failure mode recurs. Caught in PR #230 (closing #228) — `code-review-expert` flagged the secondary template block as the proximate cause the primary fix alone would not have addressed.
- **Loophole text** — the fix itself contains language that an instruction-following agent can reuse to commit the original failure (e.g., a "Sample tone" subsection that provides a placeholder policy sentence the agent rationalizes as compliant). Caught in PR #231 (closing #218) — `code-review-expert` issued NEEDS_CHANGES on candidate text that re-opened the loophole it named.

Domain-of-the-fix experts and structural reviewers do not reliably catch either mechanism. The requirement-fidelity lens is what binds them.

### Typical composition

`code-review-expert` fills one of the three minimum-fan-out slots, not a fourth. The standard composition for an agent-behavioral fix is:

- **Subject agent** — the one being corrected
- **Structural reviewer** — `docs-expert` for agent or rule changes
- **`code-review-expert`** — requirement-fidelity review of the proposed text

## Dependency Liveliness Evaluation

When research agents evaluate and recommend external libraries, tools, or utilities, they must assess whether the project is actively maintained. Recommending an abandoned or stagnating project risks unpatched security vulnerabilities, degrading platform compatibility, and no path forward for bug fixes.

### When This Applies

- Recommending an external library, CLI tool, or utility for adoption
- Comparing alternatives where project health is a differentiator
- Answering questions about whether a specific tool is suitable for production use

This does not apply to: standard library features, language builtins, well-known stable projects with obvious activity (e.g., Linux kernel, systemd, PostgreSQL), or internal/first-party code.

### Signals to Assess

| Signal | What to check |
|---|---|
| Last release date | Most recent tagged release or published package version |
| Commit recency | Commits in the last 6 months on the default branch |
| Issue/PR activity | Triaging, review, and merge activity — not just issue count |
| Contributor count | Bus-factor risk — single-maintainer projects are higher risk |
| Open issue age | Unresponded issues piling up without triage |
| CI/CD health | Automated checks running and passing on recent commits |

Not all signals carry equal weight. A project with infrequent releases but active issue triage may be in maintenance mode (healthy). A project with recent commits but hundreds of unresponded issues may be overwhelmed (unhealthy).

### Output Format

When recommending an external dependency, include a liveliness assessment:

```text
**Liveliness:** Active | Maintenance-only | Stale | Abandoned
**Last release:** <date or "none">
**Commit activity:** <description of recent activity>
**Risk level:** Low | Medium | High
```

- **Active** — regular releases, responsive issue triage, multiple contributors
- **Maintenance-only** — infrequent releases, security patches only, limited new features. Acceptable for stable, mature tools.
- **Stale** — no releases or commits in 12+ months, unresponsive maintainers. Flag the risk.
- **Abandoned** — archived repo, explicit abandonment notice, or no activity in 24+ months. Do not recommend without a strong justification and a mitigation plan.

### Risk Escalation

- **Low** — Active or Maintenance-only with multiple contributors. No action required.
- **Medium** — Maintenance-only with a single maintainer, or Stale with a viable fork. Note the risk in the recommendation.
- **High** — Stale or Abandoned with no viable fork. Recommend alternatives or flag that the user is accepting maintenance risk.

## Agent Efficacy Reporting

Every research, design, and implementation phase that invokes agents MUST include an **Agent Efficacy Report**. This is a mandatory output. Omitting it is a protocol violation.

## When to produce a report

- **Research phase:** After all parallel agents return and before presenting synthesized findings.
- **Design/planning phase:** Included in the implementation plan presented for approval.
- **Implementation phase:** After implementation is complete, report on how agent research translated into implementation and where gaps appeared.

## Report structure

Each report must include:

1. **Agent table** — for each agent invoked: name, type (custom skill / general-purpose), duration, key contributions, and value rating (High / Medium / Low).
2. **Disagreements** — where agents disagreed and which perspective was chosen and why. State "None" explicitly if agents agreed.
3. **Synergies** — how agent outputs combined or complemented each other.
4. **Custom agent feedback** — specific improvement opportunities for custom agents (content gaps, behavioral issues, performance concerns). This feeds directly into backlog issues for agent improvement.

## Purpose

Efficacy reports serve three goals:

- **Transparency** — the user sees exactly what each agent contributed and can evaluate the research quality.
- **Continuous improvement** — custom agent feedback identifies content gaps and behavioral issues that become backlog work items.
- **Process validation** — tracks whether the agent framework is producing value proportional to the time and context invested.
