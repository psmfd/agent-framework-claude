# ADR-017: Plan-before-code with sub-agent exception

**Status:** Accepted
**Date:** 2026-03-25

## Context and Problem Statement

Agents can make unexpected code changes that are difficult to undo, especially when the change spans multiple files or introduces structural modifications. Without a gate, an agent might refactor code, add features, or modify configuration before the user understands the approach being taken.

## Considered Options

* **Plan + approval gate with sub-agent exception** — agents present an implementation plan and wait for explicit user approval before modifying code; sub-agents delegated by an approved parent proceed without re-presenting
* **Plan + approval, no exceptions** — every agent, including sub-agents, must present a plan and wait for approval
* **No gate** — trust agents to make reasonable changes without prior approval

## Decision Outcome

Chosen option: **Plan + approval gate with sub-agent exception**, because it prevents unexpected changes while avoiding friction in delegated workflows. The sub-agent exception was added after experience showed that re-presenting parent-approved plans to sub-agents was unhelpful and created approval fatigue.

### Tradeoffs

* Good: user always knows what will change before it changes
* Good: plans serve as documentation of intent, making review easier
* Good: sub-agent exception keeps delegated workflows fluid
* Bad: adds a round-trip to every implementation task (acceptable for the safety it provides)
* Bad: the sub-agent exception requires trust that the parent's plan adequately covers delegated work

## More Information

* `rules/plan-before-code.md` — the enforcing rule
* Issue #27 — added the sub-agent exception
* AGENTS.md Plan Before Code section
