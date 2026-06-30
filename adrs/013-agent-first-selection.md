# ADR-013: Agent-first selection protocol for custom agents

**Status:** Accepted
**Date:** 2026-03-27

## Context and Problem Statement

Custom agents encode domain expertise, known fragilities, and validated patterns that general-purpose agents lack. Without an explicit selection protocol, agents default to general-purpose even when a better-fit custom agent exists for the task domain. This wastes the investment in custom skills and produces lower-quality results.

## Considered Options

* **Behavioral rule with inline catalog** — a rule (`agent-first-selection.md`) instructs agents to check the catalog table before delegating; validate.sh enforces catalog consistency
* **Hook-based enforcement** — a `PreToolUse` hook on the Agent tool blocks general-purpose invocations when a custom agent matches (deferred to issue #59 — domain inference from shell is infeasible)
* **Routing skill** — a dedicated skill performs programmatic catalog lookup (deferred to issue #60 — current catalog size of 8 does not justify the overhead)

## Decision Outcome

Chosen option: **Behavioral rule with inline catalog**, because it is implementable today without the unsolved domain-inference problem that blocks hook-based enforcement. The catalog table in the rule is validated against the actual `agents/` directory by validate.sh. The deferred options (#59, #60) remain viable as the catalog grows.

### Tradeoffs

* Good: immediately effective — the rule is loaded at session start and guides agent selection
* Good: validate.sh ensures the catalog stays in sync with actual agents
* Bad: enforcement is behavioral, not mechanical — agents can still choose general-purpose if they misjudge the domain
* Bad: the inline catalog table must be updated manually when agents are added or removed

## More Information

* `rules/agent-first-selection.md` — the enforcing rule
* Issue #59 — hook-based enforcement investigation (deferred)
* Issue #60 — routing skill (deferred, gated on catalog size >12)
* PR #61 — established the rule and catalog validation
