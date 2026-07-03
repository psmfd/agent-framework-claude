---
description: 'Prefer custom skill agents over general-purpose agents for domain-specific tasks, with a defined fallback and catalog-drift filing when a subagent_type does not resolve'
---

# Agent-First Selection

**Enforcement:** validate.sh check_agent_catalog (catalog table accuracy only, not routing behavior); self-report only (routing decisions)

Custom agents exist because they encode domain expertise, known fragilities, and validated patterns that general-purpose agents lack. Using a general-purpose agent when a custom agent covers the domain is a protocol violation — it discards curated knowledge in favor of generic reasoning.

## Selection Protocol

Before delegating work to an agent, follow this protocol strictly:

1. **Check whether a custom agent covers the task domain.** Consult the Available Agents catalog in AGENTS.md. Check EVERY agent — do not stop at the first plausible match. Tasks frequently touch multiple domains.
2. **If a custom agent exists, invoke it** via the Agent tool with `subagent_type` set to the agent name.
3. **If multiple custom agents are relevant, invoke all of them.** This is not optional. A task touching GitHub CLI and git workflows requires BOTH `gh-cli-expert` and `gitflow-expert`, not just whichever one you think of first.
4. **Use general-purpose agents only when no custom agent covers the domain** — the task falls outside all cataloged domains, or requires cross-domain synthesis that no single agent handles. Even then, supplement with custom agents for any domain-specific subtasks.

## Agent Catalog

The canonical catalog — one row per agent with Tier, Domain, and Use-when — is the "Available Agents" table in [AGENTS.md](../AGENTS.md), which loads into every session alongside this rule. Consult it there. This rule deliberately carries no copy: the generated mirror this section previously held was retired to eliminate an always-loaded duplicate (ADR-085); `scripts/regen-agent-catalog.sh --check` guards against the table being reintroduced here.

## Unresolvable Agent Type

If a delegation targets a `subagent_type` this catalog does not list — the name was mistyped, the agent was renamed or removed, or the catalog and the actual `agents/` directory have drifted (see the Documentation Sync Map in `CONTRIBUTING.md`) — do not silently drop the perspective from the fan-out and do not guess a near-miss name:

1. **Fall back to a general-purpose agent** carrying the identical brief (question, context, expected return contract) the custom agent would have received. The fallback counts toward the divergence minimum only under the same rule as any general-purpose substitution — see "What Counts Toward the Minimum" in `research-parallelism.md`.
2. **File a catalog-drift issue** per `file-issues-first.md` (plan step 1 if discovered during planning; otherwise file it immediately) — title it `catalog drift: <requested-name> not found in agents/`, body naming the requested name, the task that triggered it, and whether the likely cause is a typo, rename, or removal. Do not silently correct the catalog yourself mid-task — a corrected catalog is a separate reviewed change.
3. **Continue the current task** with the fallback response; the drift issue is a tracked follow-up, not a blocker for the task in progress.

This procedure applies only when the named `subagent_type` genuinely does not exist. It is not a way to avoid agent-first routing by treating an existing catalog match as "close enough to skip" — if a matching custom agent exists under a discoverable name, use it; the fallback and catalog-drift issue are for genuine absence, not routing friction.

## Narrow Exemptions

- **No matching agent for the domain** — the task falls outside all cataloged agent domains. General-purpose agents are the correct choice. But verify this by scanning the full catalog, not by assuming.
- **Operating as a subagent** — the parent session already selected the appropriate agent for the task.
- **Cross-domain synthesis** — the task requires combining perspectives from multiple domains and no single agent covers the full scope. Use the research parallelism rule to fan out across the relevant custom agents, supplementing with general-purpose agents only for uncovered domains.

## What Is NOT an Exemption

- **"Agent invocation overhead exceeds the benefit"** — this is not your call to make. The overhead of invoking an agent is seconds. The cost of skipping domain expertise is wrong answers, missed edge cases, and user trust erosion. Invoke the agent.
- **"I already know the answer"** — your confidence is not a substitute for domain expertise. The agent may surface fragilities, caveats, or patterns you are not aware of.
