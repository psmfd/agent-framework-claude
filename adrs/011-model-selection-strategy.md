# ADR-011: Model selection strategy — Opus main, Sonnet subagents

**Status:** Accepted
**Date:** 2026-03-25

## Context and Problem Statement

Subagents are invoked frequently during research, implementation, and review phases. Running every subagent on the most capable (and most expensive) model would be cost-prohibitive. However, some subagent tasks are quality-critical and benefit from a more capable model.

## Considered Options

* **Opus main + Sonnet subagents with per-agent overrides** — set `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` globally; individual agent wrappers override with `model: opus` when quality is critical
* **Opus everywhere** — use the most capable model for all agents
* **Sonnet everywhere** — use the faster model for all agents, including the main session
* **Per-agent only** — no global default, specify model in every wrapper

## Decision Outcome

Chosen option: **Opus main + Sonnet subagents with per-agent overrides**, because it balances cost and quality. The main session (where the user interacts) uses Opus for maximum capability. Read-heavy subagents like `lookup` use Sonnet (fast, cheap). Quality-critical subagents like `curator` override to Opus.

### Tradeoffs

* Good: significant cost reduction — most subagent invocations use the cheaper model
* Good: per-agent overrides let quality-critical tasks use the full model
* Good: the global default means new agents automatically get Sonnet unless explicitly overridden
* Bad: the strategy is implicit — scattered across `settings.json` and individual wrapper frontmatter with no single explanation
* Bad: model tier names change over time — "opus" and "sonnet" are relative to the current Claude generation

## More Information

* `settings.json` — `CLAUDE_CODE_SUBAGENT_MODEL: sonnet` and `effortLevel: high`
* Agent wrapper frontmatter `model:` field — per-agent overrides
