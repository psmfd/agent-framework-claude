# ADR-016: Research parallelism with minimum three agents

**Status:** Accepted
**Date:** 2026-03-25

## Context and Problem Statement

Sequential research (one agent at a time) is slow and produces single-perspective answers. When investigating unfamiliar territory, debugging, or evaluating options, a single agent's blind spots become the session's blind spots. Parallel research from multiple angles produces better-synthesized answers and surfaces disagreements that sequential research would miss.

## Considered Options

* **Minimum 3 parallel agents** — fan out research across at least 3 agents, each approaching from a different angle; synthesize best-of-breed before responding; include Agent Efficacy Report
* **Single agent per question** — research sequentially with one agent at a time
* **Unbounded parallelism** — launch as many agents as seem useful, no minimum

## Decision Outcome

Chosen option: **Minimum 3 parallel agents**, because it ensures multiple perspectives without unbounded context cost. The synthesis step forces comparison rather than defaulting to the first result. The Agent Efficacy Report provides transparency, continuous improvement feedback, and process validation.

### Tradeoffs

* Good: multiple perspectives catch blind spots and surface disagreements
* Good: efficacy reports identify custom agent SKILL.md gaps for backlog work
* Good: parallel execution is faster than sequential for the same breadth of research
* Bad: context cost — each agent consumes tokens even if its contribution is low-value
* Bad: the minimum of 3 can feel heavy for straightforward questions (mitigated by the "trivial single-step" exception in agent-first-selection)

## More Information

* `rules/research-parallelism.md` — the enforcing rule with efficacy report structure
* AGENTS.md Research Parallelism and Agent Efficacy Reporting sections
